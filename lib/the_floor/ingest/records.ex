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

  defmodule Jurisdiction do
    @moduledoc "A legislative jurisdiction (`federal`, `state`, `local`)."
    @enforce_keys [:key, :name, :classification, :source]
    defstruct [:key, :name, :classification, :source]
  end

  defmodule Body do
    @moduledoc "A legislature, chamber, committee or subcommittee."
    @enforce_keys [:jurisdiction, :external_id, :name, :classification, :source]
    defstruct [:jurisdiction, :external_id, :name, :classification, :parent_external_id, :source]
  end

  defmodule LegislativeSession do
    @moduledoc "A session of a legislature, optionally nested under a parent session."
    @enforce_keys [:jurisdiction, :identifier, :source]
    defstruct [
      :jurisdiction,
      :identifier,
      :parent_identifier,
      :name,
      :start_date,
      :end_date,
      :source
    ]
  end

  defmodule Person do
    @moduledoc "A legislator, matched across sources by any of its `{scheme, value}` identifiers."
    @enforce_keys [:identifiers, :name, :source]
    defstruct [:identifiers, :name, :given_name, :family_name, :image_url, :source]
  end

  defmodule Membership do
    @moduledoc "A person's role in a body, optionally with a district, party and term dates."
    @enforce_keys [:jurisdiction, :person, :body_external_id, :role, :source]
    defstruct [
      :jurisdiction,
      :person,
      :body_external_id,
      :role,
      :party,
      :district,
      :start_date,
      :end_date,
      :source
    ]
  end
end
