defmodule EverydayCitizen.Legislation do
  @moduledoc "Queries over bills, actions, sponsorships and text versions."
  import Ecto.Query

  alias EverydayCitizen.Legislation.{Bill, BillAction, BillSummary, BillVersion}
  alias EverydayCitizen.Legislature.Jurisdiction
  alias EverydayCitizen.Repo

  @spec get_bill(String.t(), String.t()) :: Bill.t() | nil
  def get_bill(jurisdiction_key, external_id) do
    Bill
    |> join(:inner, [b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
    |> where([b, j], j.key == ^jurisdiction_key and b.external_id == ^external_id)
    |> Repo.one()
  end

  @spec get_version(Bill.t(), String.t()) :: BillVersion.t() | nil
  def get_version(%Bill{id: bill_id}, code) do
    Repo.get_by(BillVersion, bill_id: bill_id, code: code)
  end

  @spec count_bills(integer()) :: non_neg_integer()
  def count_bills(session_id) do
    Bill |> where([b], b.session_id == ^session_id) |> Repo.aggregate(:count)
  end

  @doc "Actions the adapter could not classify, oldest first, for review."
  @spec list_unclassified_actions(pos_integer()) :: [BillAction.t()]
  def list_unclassified_actions(limit) do
    BillAction
    |> where([a], a.unclassified)
    |> order_by([a], asc: a.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Versions whose text has not been fetched yet."
  @spec versions_missing_text(pos_integer()) :: [BillVersion.t()]
  def versions_missing_text(limit) do
    BillVersion
    |> where([v], is_nil(v.text_source_id))
    |> order_by([v], asc: v.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "`{bill_external_id, code}` of every version in the jurisdiction with no text stored."
  @spec version_keys_missing_text(String.t()) :: [{String.t(), String.t()}]
  def version_keys_missing_text(jurisdiction_key) do
    BillVersion
    |> join(:inner, [v], b in Bill, on: b.id == v.bill_id)
    |> join(:inner, [_v, b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
    |> where([v, _b, j], j.key == ^jurisdiction_key and is_nil(v.text_source_id))
    |> order_by([v], asc: v.id)
    |> select([v, b], {b.external_id, v.code})
    |> Repo.all()
  end

  @doc """
  `{date, description}` of every action on the session's bills in the jurisdiction
  whose description contains `text`.
  """
  @spec actions_containing(String.t(), String.t(), String.t()) :: [{Date.t() | nil, String.t()}]
  def actions_containing(jurisdiction_key, session_identifier, text) do
    pattern = "%" <> String.replace(text, ~w(\\ % _), &("\\" <> &1)) <> "%"

    BillAction
    |> join(:inner, [a], b in Bill, on: b.id == a.bill_id)
    |> join(:inner, [_a, b], s in assoc(b, :session))
    |> join(:inner, [_a, b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
    |> where([a, _b, s, j], j.key == ^jurisdiction_key and s.identifier == ^session_identifier)
    |> where([a], like(a.description, ^pattern))
    |> select([a], {a.date, a.description})
    |> Repo.all()
  end

  @doc """
  A page of the jurisdiction's actions after `after_id`, in id order, as
  `%{id, description, raw_type, classification}`.
  """
  @spec actions_page(String.t(), integer(), pos_integer()) :: [map()]
  def actions_page(jurisdiction_key, after_id, limit) do
    BillAction
    |> join(:inner, [a], b in Bill, on: b.id == a.bill_id)
    |> join(:inner, [_a, b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
    |> where([a, _b, j], j.key == ^jurisdiction_key and a.id > ^after_id)
    |> order_by([a], asc: a.id)
    |> limit(^limit)
    |> select([a], %{
      id: a.id,
      description: a.description,
      raw_type: a.raw_type,
      classification: a.classification
    })
    |> Repo.all()
  end

  @doc "Sets each action's classification (nil marks it unclassified)."
  @spec update_action_classifications([{integer(), String.t() | nil}]) :: :ok
  def update_action_classifications(changes) do
    Repo.transaction(fn ->
      for {id, classification} <- changes do
        BillAction
        |> where([a], a.id == ^id)
        |> Repo.update_all(
          set: [classification: classification, unclassified: is_nil(classification)]
        )
      end
    end)

    :ok
  end

  @doc "The bill's most recent official summary (latest action date), or nil."
  @spec latest_summary(Bill.t()) :: BillSummary.t() | nil
  def latest_summary(%Bill{id: bill_id}) do
    BillSummary
    |> where([s], s.bill_id == ^bill_id)
    |> order_by([s], desc_nulls_last: s.action_date, desc: s.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Ids of the given bills that have no summary stored."
  @spec bill_ids_without_summary([integer()]) :: MapSet.t(integer())
  def bill_ids_without_summary(bill_ids) do
    with_summary =
      BillSummary
      |> where([s], s.bill_id in ^bill_ids)
      |> select([s], s.bill_id)
      |> distinct(true)
      |> Repo.all()

    MapSet.difference(MapSet.new(bill_ids), MapSet.new(with_summary))
  end

  @doc "Up to `limit` of a jurisdiction's bills with no `web_url`, as `%{id, external_id, source_url}`."
  @spec bills_without_web_url(String.t(), pos_integer()) :: [map()]
  def bills_without_web_url(jurisdiction_key, limit) do
    Bill
    |> join(:inner, [b], j in assoc(b, :jurisdiction))
    |> join(:inner, [b], s in assoc(b, :source))
    |> where([b, j], j.key == ^jurisdiction_key and is_nil(b.web_url))
    |> order_by([b], asc: b.id)
    |> limit(^limit)
    |> select([b, _j, s], %{id: b.id, external_id: b.external_id, source_url: s.url})
    |> Repo.all()
  end

  @doc "Stores a bill's official page for people."
  @spec put_web_url(integer(), String.t()) :: :ok
  def put_web_url(bill_id, url) do
    Bill |> where([b], b.id == ^bill_id) |> Repo.update_all(set: [web_url: url])
    :ok
  end

  @doc """
  Up to `limit` versions with stored XML whose sections are missing or were split
  by a format other than `format`, as `%{id, xml}`.
  """
  @spec versions_needing_sections(pos_integer(), pos_integer()) :: [
          %{id: integer(), xml: String.t()}
        ]
  def versions_needing_sections(format, limit) do
    BillVersion
    |> where([v], not is_nil(v.xml))
    |> where([v], is_nil(v.sections_version) or v.sections_version != ^format)
    |> order_by([v], asc: v.id)
    |> limit(^limit)
    |> select([v], %{id: v.id, xml: v.xml})
    |> Repo.all()
  end

  @doc "Stores a version's sections and the format they were split with."
  @spec put_sections(integer(), [map()], pos_integer()) :: :ok
  def put_sections(version_id, sections, format) do
    BillVersion
    |> where([v], v.id == ^version_id)
    |> Repo.update_all(set: [sections: sections, sections_version: format])

    :ok
  end

  @doc "Each bill's latest action (highest position), keyed by bill id."
  @spec latest_actions([integer()]) :: %{integer() => BillAction.t()}
  def latest_actions([]), do: %{}

  def latest_actions(bill_ids) do
    BillAction
    |> where([a], a.bill_id in ^bill_ids)
    |> distinct([a], a.bill_id)
    |> order_by([a], asc: a.bill_id, desc: a.position)
    |> Repo.all()
    |> Map.new(&{&1.bill_id, &1})
  end

  @doc "Each bill's latest official summary, keyed by bill id."
  @spec latest_summaries([integer()]) :: %{integer() => BillSummary.t()}
  def latest_summaries([]), do: %{}

  def latest_summaries(bill_ids) do
    BillSummary
    |> where([s], s.bill_id in ^bill_ids)
    |> distinct([s], s.bill_id)
    |> order_by([s], asc: s.bill_id, desc_nulls_last: s.action_date, desc: s.id)
    |> Repo.all()
    |> Map.new(&{&1.bill_id, &1})
  end

  @doc "A bill's committee steps, oldest first, with each committee preloaded when stored."
  @spec committee_activities(integer()) :: [EverydayCitizen.Legislation.BillCommitteeActivity.t()]
  def committee_activities(bill_id) do
    from(a in EverydayCitizen.Legislation.BillCommitteeActivity,
      where: a.bill_id == ^bill_id,
      order_by: [asc_nulls_last: a.date, asc: a.id],
      preload: :body
    )
    |> Repo.all()
  end

  @doc "The external ids of a bill's related measures of one kind (`procedural` or `related`)."
  @spec related_refs(integer(), String.t()) :: [String.t()]
  def related_refs(bill_id, kind) do
    from(r in EverydayCitizen.Legislation.BillRelation,
      where: r.bill_id == ^bill_id and r.kind == ^kind,
      select: r.related_ref
    )
    |> Repo.all()
  end

  @doc "A bill's amendments, by latest action date."
  @spec amendments(integer()) :: [EverydayCitizen.Legislation.BillAmendment.t()]
  def amendments(bill_id) do
    from(a in EverydayCitizen.Legislation.BillAmendment,
      where: a.bill_id == ^bill_id,
      order_by: [asc_nulls_last: a.latest_action_date, asc: a.id]
    )
    |> Repo.all()
  end

  @doc "External ids of the jurisdiction's bills with two or more text versions."
  @spec multi_version_bill_ids(String.t()) :: [String.t()]
  def multi_version_bill_ids(jurisdiction_key) do
    from(b in Bill,
      join: j in assoc(b, :jurisdiction),
      join: v in BillVersion,
      on: v.bill_id == b.id,
      where: j.key == ^jurisdiction_key,
      group_by: b.external_id,
      having: count(v.id) >= 2,
      select: b.external_id
    )
    |> Repo.all()
  end

  @doc "External ids of stored amendments that already have a description."
  @spec described_amendment_ids() :: MapSet.t(String.t())
  def described_amendment_ids do
    from(a in EverydayCitizen.Legislation.BillAmendment,
      where: not is_nil(a.description) and a.description != "",
      select: a.external_id
    )
    |> Repo.all()
    |> MapSet.new()
  end
end
