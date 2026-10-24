defmodule EverydayCitizen.Summaries.Credentials do
  @moduledoc """
  The header that authenticates calls to Claude.

  In production, Workload Identity Federation: the machine asks Fly for a signed
  identity token (OIDC, over the `/.fly/api` socket, a fresh one each time since
  tokens are single-use) and exchanges it at Anthropic's `/v1/oauth/token` for a
  short-lived access token, so no API key is stored or needs rotating. The token
  is cached in this process and renewed when less than two minutes remain; one
  exchange runs at a time. Without federation configured, an `ANTHROPIC_API_KEY`
  is used (development); with neither, summaries are off.
  """
  use GenServer

  @exchange_url "https://api.anthropic.com/v1/oauth/token"
  @oidc_url "http://localhost/v1/tokens/oidc"
  @renew_margin_seconds 120

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec auth_header() :: {:ok, {String.t(), String.t()}} | {:error, term()}
  def auth_header do
    cond do
      federation() -> GenServer.call(__MODULE__, :bearer, 30_000)
      key = api_key() -> {:ok, {"x-api-key", key}}
      true -> {:error, :disabled}
    end
  end

  @doc "Whether federation or an API key is configured (no network call)."
  @spec configured?() :: boolean()
  def configured?, do: not is_nil(federation() || api_key())

  @doc "Forgets the cached token (tests, or after changing configuration)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_call(:reset, _from, _state), do: {:reply, :ok, nil}

  def handle_call(:bearer, _from, state) do
    now = System.system_time(:second)

    case state do
      %{token: token, expires_at: expires_at} when expires_at - now > @renew_margin_seconds ->
        {:reply, {:ok, bearer(token)}, state}

      _stale_or_none ->
        case safely(fn -> exchange(federation()) end) do
          {:ok, token, expires_in} ->
            {:reply, {:ok, bearer(token)}, %{token: token, expires_at: now + expires_in}}

          {:error, _} = error ->
            {:reply, error, nil}
        end
    end
  end

  defp bearer(token), do: {"authorization", "Bearer " <> token}

  # a malformed reply must not crash the cache (callers would exit with it)
  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, error}
  end

  defp exchange(federation) do
    with {:ok, jwt} <- identity_token(federation.audience) do
      body = %{
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
        federation_rule_id: federation.rule_id,
        organization_id: federation.organization_id,
        service_account_id: federation.service_account_id,
        workspace_id: federation.workspace_id
      }

      [url: @exchange_url, json: body, receive_timeout: 15_000]
      |> Keyword.merge(Application.get_env(:everyday_citizen, :anthropic_req_options, []))
      |> Req.post()
      |> case do
        {:ok,
         %Req.Response{status: 200, body: %{"access_token" => token, "expires_in" => expires_in}}} ->
          {:ok, token, expires_in}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http_status, status}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # A signed identity token for this machine from Fly (single-use: one per exchange).
  defp identity_token(audience) do
    [url: @oidc_url, json: %{aud: audience}, unix_socket: "/.fly/api", receive_timeout: 10_000]
    |> Keyword.merge(Application.get_env(:everyday_citizen, :fly_oidc_req_options, []))
    |> Req.post()
    |> case do
      {:ok, %Req.Response{status: 200, body: jwt}} when is_binary(jwt) and jwt != "" ->
        {:ok, String.trim(jwt)}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:fly_oidc, status}}

      {:error, reason} ->
        {:error, {:fly_oidc, reason}}
    end
  end

  defp federation do
    case Application.get_env(:everyday_citizen, :anthropic_federation) do
      %{rule_id: rule} = federation when is_binary(rule) and rule != "" -> federation
      _ -> nil
    end
  end

  defp api_key do
    case Application.get_env(:everyday_citizen, :anthropic_api_key) do
      key when is_binary(key) and key != "" -> key
      _ -> nil
    end
  end
end
