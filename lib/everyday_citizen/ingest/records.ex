defmodule EverydayCitizen.Ingest.Records do
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

  defmodule PostalDistricts do
    @moduledoc """
    A jurisdiction's complete postal-code-to-district table; replaces whatever is
    stored. Each row is `%{postal_code, district_key, land_share}`.
    """
    @enforce_keys [:jurisdiction, :rows, :source]
    defstruct [:jurisdiction, :rows, :source]

    @type t :: %__MODULE__{}
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

  defmodule Bill do
    @moduledoc """
    A bill or resolution within a session. `web_url` is its official page for
    people, when the source has one (unlike `source.url`, which may be an API).
    """
    @enforce_keys [:jurisdiction, :session_identifier, :external_id, :identifier, :title, :source]
    defstruct [
      :jurisdiction,
      :session_identifier,
      :external_id,
      :web_url,
      :identifier,
      :classification,
      :title,
      :from_body_external_id,
      :introduced_on,
      :updated_at_source,
      :source,
      subjects: []
    ]
  end

  defmodule BillAction do
    @moduledoc """
    One action on a bill. `position` is its 0-based chronological order within the bill's action list (oldest = 0).
    A nil `classification` marks the action as unclassified (raw text kept).
    """
    @enforce_keys [:position, :description]
    defstruct [
      :position,
      :date,
      :description,
      :raw_type,
      :raw_code,
      :classification,
      :actor_body_external_id
    ]
  end

  defmodule BillActions do
    @moduledoc "The complete action list of a bill; replaces whatever is stored."
    @enforce_keys [:jurisdiction, :bill_external_id, :actions, :source]
    defstruct [:jurisdiction, :bill_external_id, :actions, :source]
  end

  defmodule BillCommittees do
    @moduledoc """
    A bill's committee steps; replaces whatever is stored. Each is
    `%{body_external_id, kind, date}`, kind one of `referred markup reported other`.
    """
    @enforce_keys [:jurisdiction, :bill_external_id, :activities, :source]
    defstruct [:jurisdiction, :bill_external_id, :activities, :source]
    @type t :: %__MODULE__{}
  end

  defmodule BillRelations do
    @moduledoc """
    Measures related to a bill; replaces whatever is stored. Each is
    `%{bill_external_id, kind}`, kind `procedural` (governs how it is taken up) or `related`.
    """
    @enforce_keys [:jurisdiction, :bill_external_id, :relations, :source]
    defstruct [:jurisdiction, :bill_external_id, :relations, :source]
    @type t :: %__MODULE__{}
  end

  defmodule BillAmendments do
    @moduledoc """
    A bill's amendments; replaces whatever is stored. Each is `%{external_id,
    identifier, description, latest_action, latest_action_date, url}`.
    """
    @enforce_keys [:jurisdiction, :bill_external_id, :amendments, :source]
    defstruct [:jurisdiction, :bill_external_id, :amendments, :source]
    @type t :: %__MODULE__{}
  end

  defmodule BillSummaries do
    @moduledoc """
    The complete set of a bill's official summaries by one author; replaces whatever
    is stored. Each entry is `%{version_code, action_date, action_description, html,
    updated_at_source}`, `html` already sanitized.
    """
    @enforce_keys [:jurisdiction, :bill_external_id, :author, :summaries, :source]
    defstruct [:jurisdiction, :bill_external_id, :author, :summaries, :source]

    @type t :: %__MODULE__{}
  end

  defmodule Sponsorships do
    @moduledoc """
    The complete sponsor/cosponsor list of a bill; replaces whatever is stored.
    Each entry is `%{person: {scheme, value}, classification: "primary" | "cosponsor",
    date: Date.t() | nil, withdrawn_on: Date.t() | nil}`.
    """
    @enforce_keys [:jurisdiction, :bill_external_id, :sponsorships, :source]
    defstruct [:jurisdiction, :bill_external_id, :sponsorships, :source]
  end

  defmodule BillVersion do
    @moduledoc "A text version of a bill (metadata only; text arrives as `BillVersionText`)."
    @enforce_keys [:jurisdiction, :bill_external_id, :code, :source]
    defstruct [
      :jurisdiction,
      :bill_external_id,
      :code,
      :classification,
      :date,
      :xml_url,
      :text_url,
      :source
    ]
  end

  defmodule BillVersionText do
    @moduledoc """
    Fetched text for an existing bill version. `xml_schema` is `uslm` or `other`;
    `sections` is the text split into sections (see the adapter's section parser)
    and `sections_version` the parser's output format.
    """
    @enforce_keys [:jurisdiction, :bill_external_id, :code, :source]
    defstruct [
      :jurisdiction,
      :bill_external_id,
      :code,
      :xml,
      :xml_schema,
      :plain_text,
      :sections,
      :sections_version,
      :source
    ]
  end

  defmodule Vote do
    @moduledoc """
    A recorded vote with its tallies and per-person positions; positions replace the stored set.
    `description` is what was voted on in the source's words; `subject_ref` and `subject_url`
    name it and its official page when it is not the bill (a nomination, an amendment).
    Each position is `%{person: {scheme, value} | nil, raw_label, option, raw_option}` where
    `option` is one of `yea nay present absent`.
    """
    @enforce_keys [
      :jurisdiction,
      :body_external_id,
      :session_identifier,
      :external_id,
      :voted_at,
      :source
    ]
    defstruct [
      :jurisdiction,
      :body_external_id,
      :session_identifier,
      :external_id,
      :identifier,
      :question,
      :description,
      :subject_ref,
      :subject_url,
      :classification,
      :result,
      :passed,
      :voted_at,
      :bill_external_id,
      :source,
      counts: %{yea: 0, nay: 0, present: 0, absent: 0},
      positions: []
    ]
  end

  defmodule VoteSubject do
    @moduledoc """
    The official record a stored vote was on, found after the vote was written
    (a nomination, an amendment): its reference and page. Only those two fields
    of the vote change; a vote not stored is skipped.
    """
    @enforce_keys [:jurisdiction, :body_external_id, :session_identifier, :external_id]
    defstruct [
      :jurisdiction,
      :body_external_id,
      :session_identifier,
      :external_id,
      :subject_ref,
      :subject_url
    ]
  end

  defmodule Event do
    @moduledoc """
    A calendar item (floor, hearing, markup). `bill_external_ids` are links to attempt;
    `raw_bill_labels` are labels the adapter could not normalize. `status` is the raw source status.
    """
    @enforce_keys [:jurisdiction, :external_id, :classification, :start_at, :source]
    defstruct [
      :jurisdiction,
      :body_external_id,
      :external_id,
      :classification,
      :raw_classification,
      :title,
      :start_at,
      :location,
      :source,
      status: "scheduled",
      all_day: false,
      bill_external_ids: [],
      raw_bill_labels: []
    ]
  end
end
