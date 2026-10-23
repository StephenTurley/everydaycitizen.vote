defmodule TheFloor.Legislation do
  @moduledoc "Queries over bills, actions, sponsorships and text versions."
  import Ecto.Query

  alias TheFloor.Legislation.{Bill, BillAction, BillVersion}
  alias TheFloor.Legislature.Jurisdiction
  alias TheFloor.Repo

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
end
