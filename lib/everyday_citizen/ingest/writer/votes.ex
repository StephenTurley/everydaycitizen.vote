defmodule EverydayCitizen.Ingest.Writer.Votes do
  @moduledoc """
  Persists votes and their positions. Natural key `(body, session, external_id)`.

  Positions replace the vote's set: because `person_id` is nullable (unknown
  people are kept with `raw_label`), the vote's positions are deleted and
  re-inserted inside the same transaction. A vote whose bill is unknown (or nil)
  is saved with `bill_id: nil`, and a position whose person is unknown with
  `person_id: nil`; the source references (`bill_ref`, `person_scheme`/`person_value`)
  are always stored so `EverydayCitizen.Ingest.Relink` can link them later. An unknown or
  missing body, or an unknown session, is
  `{:error, {:unknown_body | :unknown_session, id}}`. Returns `{:ok, vote}`.
  """
  import Ecto.Query

  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Ingest.Writer.Support
  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Legislature
  alias EverydayCitizen.Legislature.Session
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Votes.{Vote, VotePosition}

  import Support, only: [fetch: 4, jurisdiction: 1, upsert: 3]

  @spec write(Records.Vote.t(), integer() | nil) :: {:ok, Vote.t()} | {:error, term()}
  def write(%Records.Vote{} = r, run_id) do
    Support.transact(r, run_id, &do_write(r, &1))
  end

  # A vote always belongs to a body.
  defp do_write(%{body_external_id: nil}, _source_id), do: {:error, {:unknown_body, nil}}

  defp do_write(r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, body} <- Support.body(j.id, r.body_external_id),
         {:ok, session} <-
           fetch(
             Session,
             [jurisdiction_id: j.id, identifier: r.session_identifier],
             :unknown_session,
             r.session_identifier
           ),
         {:ok, vote} <-
           upsert(
             Vote,
             %{
               body_id: body.id,
               session_id: session.id,
               bill_id: bill_id(r),
               bill_ref: r.bill_external_id,
               external_id: r.external_id,
               identifier: r.identifier,
               question: r.question,
               description: r.description,
               subject_ref: r.subject_ref,
               subject_url: r.subject_url,
               classification: r.classification || "other",
               result: r.result,
               passed: r.passed,
               voted_at: r.voted_at,
               yea_count: r.counts.yea,
               nay_count: r.counts.nay,
               present_count: r.counts.present,
               absent_count: r.counts.absent,
               source_id: source_id
             },
             [:body_id, :session_id, :external_id]
           ),
         :ok <- replace_positions(vote, r.positions, source_id) do
      {:ok, vote}
    end
  end

  @doc "Sets a stored vote's subject reference and page; `{:ok, 0}` when the vote is not stored."
  @spec write_subject(Records.VoteSubject.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def write_subject(%Records.VoteSubject{} = r) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, body} <- Support.body(j.id, r.body_external_id),
         {:ok, session} <-
           fetch(
             Session,
             [jurisdiction_id: j.id, identifier: r.session_identifier],
             :unknown_session,
             r.session_identifier
           ) do
      {count, _} =
        Repo.update_all(
          from(v in Vote,
            where:
              v.body_id == ^body.id and v.session_id == ^session.id and
                v.external_id == ^r.external_id
          ),
          set: [subject_ref: r.subject_ref, subject_url: r.subject_url]
        )

      {:ok, count}
    end
  end

  defp bill_id(%{bill_external_id: nil}), do: nil

  defp bill_id(r) do
    case Legislation.get_bill(r.jurisdiction, r.bill_external_id) do
      nil -> nil
      bill -> bill.id
    end
  end

  # One person lookup and one insert for the whole set: a large chamber's vote has ~430
  # positions, and a query per position ran past the transaction timeout.
  defp replace_positions(vote, positions, source_id) do
    people =
      positions
      |> Enum.map(& &1.person)
      |> Enum.reject(&is_nil/1)
      |> Legislature.person_ids_by_identifiers()

    now = DateTime.utc_now()

    changesets =
      Enum.map(positions, fn p ->
        {scheme, value} = p.person || {nil, nil}

        VotePosition.changeset(%VotePosition{}, %{
          vote_id: vote.id,
          person_id: p.person && Map.get(people, p.person),
          person_scheme: scheme,
          person_value: value,
          raw_label: p.raw_label,
          option: p.option,
          raw_option: p.raw_option,
          source_id: source_id
        })
      end)

    case Enum.find(changesets, &(not &1.valid?)) do
      nil ->
        Repo.delete_all(from p in VotePosition, where: p.vote_id == ^vote.id)
        rows = Enum.map(changesets, &row(&1, now))
        rows |> Enum.chunk_every(1000) |> Enum.each(&Repo.insert_all(VotePosition, &1))
        :ok

      invalid ->
        {:error, invalid}
    end
  end

  defp row(changeset, now) do
    changeset
    |> Ecto.Changeset.apply_changes()
    |> Map.take(VotePosition.__schema__(:fields) -- [:id])
    |> Map.merge(%{inserted_at: now, updated_at: now})
  end
end
