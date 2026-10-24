defmodule EverydayCitizen.Adapters.Federal.HTTP do
  @moduledoc """
  Rate-limited, retrying HTTP GET for federal sources. Returns the decoded body,
  the raw body and a `SourceRef` (url without `api_key`, hash of the raw body).
  """
  alias EverydayCitizen.Ingest.RateLimiter
  alias EverydayCitizen.Ingest.Records.SourceRef

  @user_agent "EverydayCitizen/0.1 (+https://everydaycitizen.vote)"

  @spec get(String.t(), keyword()) ::
          {:ok, %{body: term(), raw: binary(), source: SourceRef.t()}} | {:error, term()}
  def get(url, opts \\ []) do
    params = Keyword.get(opts, :params, [])
    decode = Keyword.get(opts, :decode, :json)
    if limiter = opts[:limiter], do: RateLimiter.acquire(limiter)

    req =
      :everyday_citizen
      |> Application.get_env(:federal_req_options, [])
      |> Req.new()
      |> Req.merge(
        headers: [{"user-agent", @user_agent}],
        params: params,
        decode_body: false,
        raw: true
      )
      |> Req.merge(Keyword.get(opts, :req, []))

    case Req.get(req, url: url) do
      {:ok, %Req.Response{status: 200, body: raw}} when is_binary(raw) ->
        with {:ok, body} <- decode(raw, decode) do
          {:ok, %{body: body, raw: raw, source: SourceRef.new(source_url(url, params), raw)}}
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  True when a 200 response body is an HTML page. Several sources (GovInfo,
  docs.house.gov) answer 200 with an HTML page instead of 404 for a missing file.
  """
  @spec html?(binary()) :: boolean()
  def html?(raw) do
    head =
      raw
      |> binary_part(0, min(byte_size(raw), 512))
      |> String.trim_leading()
      |> String.downcase()

    String.starts_with?(head, ["<!doctype html", "<html"])
  end

  defp decode(raw, :raw), do: {:ok, raw}

  defp decode(raw, :json) do
    case JSON.decode(raw) do
      {:ok, term} -> {:ok, term}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp source_url(url, params) do
    visible = Enum.reject(params, fn {k, _} -> to_string(k) == "api_key" end)
    if visible == [], do: url, else: url <> "?" <> URI.encode_query(visible)
  end
end
