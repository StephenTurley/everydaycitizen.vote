defmodule EverydayCitizen.Adapters.Federal.CongressGov do
  @moduledoc "Client for the Congress.gov API v3."
  alias EverydayCitizen.Adapters.Federal.HTTP
  alias EverydayCitizen.Ingest.Records.SourceRef

  @base "https://api.congress.gov/v3"
  @page_size 250

  @spec get(String.t(), keyword()) :: {:ok, map(), SourceRef.t()} | {:error, term()}
  def get(path, params \\ []) do
    params =
      params ++
        [
          format: "json",
          api_key: Application.fetch_env!(:everyday_citizen, :congress_gov_api_key)
        ]

    with {:ok, %{body: body, source: source}} <-
           HTTP.get(@base <> path, limiter: :congress_gov, params: params) do
      {:ok, body, source}
    end
  end

  @doc "Lazily streams `{item, source_ref}` across all pages of a list endpoint."
  @spec paginate(String.t(), String.t(), keyword()) :: Enumerable.t()
  def paginate(path, list_key, params \\ []) do
    first = {path, Keyword.put_new(params, :limit, @page_size)}

    first
    |> Stream.unfold(fn
      nil ->
        nil

      {path, params} ->
        case get(path, params) do
          {:ok, body, source} ->
            items = body |> Map.get(list_key, []) |> Enum.map(&{&1, source})
            {items, next_request(body)}

          {:error, reason} ->
            raise "Congress.gov request failed for #{path}: #{inspect(reason)}"
        end
    end)
    |> Stream.flat_map(& &1)
  end

  @doc """
  Every item of a list endpoint with the first page's source (`nil` when there
  are no items). A failed request is returned as `{:error, message}`.
  """
  @spec fetch_all(String.t(), String.t()) ::
          {:ok, {[map()], SourceRef.t() | nil}} | {:error, String.t()}
  def fetch_all(path, key) do
    items = path |> paginate(key) |> Enum.to_list()
    source = items |> List.first() |> then(&(&1 && elem(&1, 1)))
    {:ok, {Enum.map(items, &elem(&1, 0)), source}}
  rescue
    e in RuntimeError -> {:error, Exception.message(e)}
  end

  @spec count(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(path, params \\ []) do
    with {:ok, body, _source} <- get(path, Keyword.put(params, :limit, 1)) do
      {:ok, get_in(body, ["pagination", "count"]) || 0}
    end
  end

  defp next_request(%{"pagination" => %{"next" => next}}) when is_binary(next) do
    %URI{path: "/v3" <> path, query: query} = URI.parse(next)

    params =
      (query || "")
      |> URI.decode_query()
      |> Enum.reject(fn {k, _} -> k in ["api_key", "format"] end)

    {path, params}
  end

  defp next_request(_), do: nil
end
