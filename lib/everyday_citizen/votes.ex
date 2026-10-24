defmodule EverydayCitizen.Votes do
  @moduledoc "Queries over votes and their positions."
  import Ecto.Query

  alias EverydayCitizen.Repo
  alias EverydayCitizen.Votes.Vote

  @spec count_votes(integer(), integer()) :: non_neg_integer()
  def count_votes(body_id, session_id) do
    Vote
    |> where([v], v.body_id == ^body_id and v.session_id == ^session_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  A body's votes with no official page yet for what they were on, as
  `%{external_id, session_identifier, question, description, subject_ref,
  bill_external_id}` (the bill's external id, or the source's reference to an
  unknown one).
  """
  @spec awaiting_subjects(String.t(), String.t()) :: [map()]
  def awaiting_subjects(jurisdiction_key, body_external_id) do
    from(v in Vote,
      join: b in assoc(v, :body),
      join: j in assoc(b, :jurisdiction),
      join: s in assoc(v, :session),
      left_join: bill in assoc(v, :bill),
      where:
        j.key == ^jurisdiction_key and b.external_id == ^body_external_id and
          is_nil(v.subject_url),
      select: %{
        external_id: v.external_id,
        session_identifier: s.identifier,
        question: v.question,
        description: v.description,
        subject_ref: v.subject_ref,
        bill_external_id: coalesce(bill.external_id, v.bill_ref)
      }
    )
    |> Repo.all()
  end

  @doc "The subset of `external_ids` that already have a stored vote."
  @spec existing_external_ids([String.t()]) :: MapSet.t(String.t())
  def existing_external_ids(external_ids) do
    Vote
    |> where([v], v.external_id in ^external_ids)
    |> select([v], v.external_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "`%{external_id => {yea_count, nay_count}}` for the stored votes among `external_ids`."
  @spec tallies([String.t()]) :: %{String.t() => {integer(), integer()}}
  def tallies(external_ids) do
    Vote
    |> where([v], v.external_id in ^external_ids)
    |> select([v], {v.external_id, {v.yea_count, v.nay_count}})
    |> Repo.all()
    |> Map.new()
  end

  @doc "A page of the jurisdiction's votes after `after_id`, in id order, as `%{id, question, classification}`."
  @spec questions_page(String.t(), integer(), pos_integer()) :: [map()]
  def questions_page(jurisdiction_key, after_id, limit) do
    Vote
    |> join(:inner, [v], b in assoc(v, :body))
    |> join(:inner, [_v, b], j in EverydayCitizen.Legislature.Jurisdiction,
      on: j.id == b.jurisdiction_id
    )
    |> where([v, _b, j], j.key == ^jurisdiction_key and v.id > ^after_id)
    |> order_by([v], asc: v.id)
    |> limit(^limit)
    |> select([v], %{id: v.id, question: v.question, classification: v.classification})
    |> Repo.all()
  end

  @doc "Sets each vote's type."
  @spec reclassify([{integer(), String.t()}]) :: :ok
  def reclassify(changes) do
    Repo.transaction(fn ->
      for {id, classification} <- changes do
        Vote |> where([v], v.id == ^id) |> Repo.update_all(set: [classification: classification])
      end
    end)

    :ok
  end
end
