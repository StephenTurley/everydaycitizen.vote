defmodule TheFloor.Ingest.Records do
  @moduledoc """
  Normalized structs that adapters produce and the ingest writer consumes.
  """

  defmodule SourceRef do
    @moduledoc "Provenance for a fetched document: where it came from, when, and its hash."
    @enforce_keys [:url, :fetched_at, :content_hash]
    defstruct [:url, :fetched_at, :content_hash]

    @type t :: %__MODULE__{url: String.t(), fetched_at: DateTime.t(), content_hash: String.t()}

    @doc "Builds a ref, hashing the raw response body (lowercase hex SHA-256)."
    @spec new(String.t(), binary(), DateTime.t()) :: t()
    def new(url, body, fetched_at \\ DateTime.utc_now()) when is_binary(body) do
      %__MODULE__{
        url: url,
        fetched_at: fetched_at,
        content_hash: :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)
      }
    end
  end
end
