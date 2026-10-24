defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncSenateVotes do
  @moduledoc """
  Syncs Senate roll-call votes from Voteview's bulk files (`Federal.Voteview`):
  three requests per run, whatever the number of votes. Writes every vote not yet
  stored plus the most recent of each session (Voteview corrects recent votes as
  they are reconciled). With a `session` arg only that session is written;
  otherwise every stored session of the congress is. Snoozes until the congress
  has a stored session and people are stored.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{Job, Prerequisites, Sessions, Voteview}
  alias EverydayCitizen.Adapters.Federal.Normalize.SenateVoteview
  alias EverydayCitizen.{Ingest, Votes}

  @recent 10

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    congress = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]
    checks = [Prerequisites.child_sessions(congress), Prerequisites.people()]

    with :ok <- Prerequisites.check(job, checks), do: sync(congress, args)
  end

  defp sync(congress, args) do
    Job.run("sync_senate_votes", fn run_id, _cursor ->
      with {:ok, files, source} <- Voteview.files(congress) do
        sessions = Sessions.numbers(congress, args["session"])

        files
        |> SenateVoteview.votes(source)
        |> Enum.group_by(&session_number/1)
        |> Map.take(sessions)
        |> Enum.reduce_while({:ok, %{}}, &write_session(&1, &2, congress, run_id))
      end
    end)
  end

  defp write_session({session, votes}, {:ok, stats}, congress, run_id) do
    case write(votes, run_id) do
      {:ok, n} -> {:cont, {:ok, Map.put(stats, "#{congress}-#{session}", n)}}
      error -> {:halt, error}
    end
  end

  defp session_number(vote),
    do: vote.session_identifier |> String.split("-") |> List.last() |> String.to_integer()

  defp write(votes, run_id) do
    wanted = to_write(votes)

    Enum.reduce_while(wanted, {:ok, %{written: 0, listed: length(votes)}}, fn vote, {:ok, s} ->
      case Ingest.write(vote, run_id) do
        {:ok, _} -> {:cont, {:ok, %{s | written: s.written + 1}}}
        {:error, reason} -> {:halt, {:error, {vote.external_id, reason}}}
      end
    end)
  end

  # Votes not stored yet, plus the most recent few (votes are in roll order).
  defp to_write(votes) do
    stored = votes |> Enum.map(& &1.external_id) |> Votes.existing_external_ids()
    recent = votes |> Enum.take(-@recent) |> MapSet.new(& &1.external_id)

    Enum.filter(votes, &(not MapSet.member?(stored, &1.external_id) or &1.external_id in recent))
  end
end
