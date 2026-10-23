defmodule TheFloor.Ingest.Writer.Votes do
  @moduledoc """
  Persists votes and their positions. Natural key `(body, session, external_id)`.

  Positions replace the vote's set: because `person_id` is nullable (unknown
  people are kept with `raw_label`), the vote's positions are deleted and
  re-inserted inside the same transaction. A vote whose bill is unknown (or nil)
  is saved with `bill_id: nil`; an unknown body or session is
  `{:error, {:unknown_body | :unknown_session, id}}`. Returns `{:ok, vote}`.
  """
  import Ecto.Query

  alias TheFloor.Ingest.Records
  alias TheFloor.Ingest.Writer.Support
  alias TheFloor.Legislation
  alias TheFloor.Legislature
  alias TheFloor.Legislature.Session
  alias TheFloor.Repo
  alias TheFloor.Votes.{Vote, VotePosition}

  import Support, only: [fetch: 4, jurisdiction: 1, upsert: 3]

  @spec write(Records.Vote.t(), integer() | nil) :: {:ok, Vote.t()} | {:error, term()}
  def write(%Records.Vote{} = r, run_id) do
    Support.transact(r, run_id, &do_write(r, &1))
  end

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
               external_id: r.external_id,
               identifier: r.identifier,
               question: r.question,
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

  defp bill_id(%{bill_external_id: nil}), do: nil

  defp bill_id(r) do
    case Legislation.get_bill(r.jurisdiction, r.bill_external_id) do
      nil -> nil
      bill -> bill.id
    end
  end

  defp replace_positions(vote, positions, source_id) do
    Repo.delete_all(from p in VotePosition, where: p.vote_id == ^vote.id)

    Enum.reduce_while(positions, :ok, fn p, :ok ->
      attrs = %{
        vote_id: vote.id,
        person_id: person_id(p.person),
        raw_label: p.raw_label,
        option: p.option,
        raw_option: p.raw_option,
        source_id: source_id
      }

      case Repo.insert(VotePosition.changeset(%VotePosition{}, attrs)) do
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp person_id(nil), do: nil

  defp person_id({scheme, value}) do
    case Legislature.get_person_by_identifier(scheme, value) do
      nil -> nil
      person -> person.id
    end
  end
end
