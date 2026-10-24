defmodule EverydayCitizen.Adapters.Federal.Jobs.LinkVoteSubjects do
  @moduledoc """
  Links Senate votes to the official record they were on when it is not a bill
  (`Normalize.VoteSubjects`): nominations, through the Congress.gov nomination
  list (only when some vote needs one), and amendments, through each voted-on
  bill's amendment list. Only votes without a page yet are looked at, so a
  nightly run costs little; a vote whose record can't be confirmed keeps its
  reference and no page, and is tried again the next night.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{CongressGov, Job}
  alias EverydayCitizen.Adapters.Federal.Normalize.VoteSubjects
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records.VoteSubject
  alias EverydayCitizen.Votes

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    congress = args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]

    Job.run("link_vote_subjects", fn run_id, _cursor -> link(congress, run_id) end)
  end

  defp link(congress, run_id) do
    votes =
      "federal"
      |> Votes.awaiting_subjects("senate")
      |> Enum.filter(&String.starts_with?(&1.session_identifier, "#{congress}-"))

    nominations = Enum.filter(votes, &match?("PN" <> _, &1.subject_ref || ""))
    amendments = Enum.filter(votes, &(&1.bill_external_id && amendment?(&1.question)))

    nomination_links = nomination_links(nominations, congress)
    amendment_links = amendment_links(amendments, congress)

    with :ok <- write(nomination_links ++ amendment_links, run_id) do
      {:ok,
       %{
         nominations: length(nomination_links),
         amendments: length(amendment_links),
         unlinked:
           length(nominations) + length(amendments) - length(nomination_links) -
             length(amendment_links)
       }}
    end
  end

  defp amendment?(question), do: is_binary(question) and question =~ ~r/amendment/i

  defp nomination_links([], _congress), do: []

  defp nomination_links(votes, congress) do
    by_citation =
      "/nomination/#{congress}"
      |> CongressGov.paginate("nominations")
      |> Enum.map(&elem(&1, 0))
      |> VoteSubjects.by_citation()

    for vote <- votes,
        {citation, url} <- [
          VoteSubjects.nomination_link(vote.subject_ref, vote.description, by_citation)
        ],
        do: {vote, citation, url}
  end

  defp amendment_links(votes, congress) do
    votes
    |> Enum.group_by(& &1.bill_external_id)
    |> Enum.flat_map(fn {bill, bill_votes} ->
      rolls = bill |> amendments(congress) |> VoteSubjects.amendment_rolls(congress)

      for vote <- bill_votes,
          {ref, url} <- [Map.get(rolls, session_roll(vote.external_id))],
          do: {vote, ref, url}
    end)
  end

  # "119-s-5" → the bill's amendment list
  defp amendments(bill_external_id, congress) do
    this_congress = "#{congress}"

    case String.split(bill_external_id, "-") do
      [^this_congress, type, number] ->
        "/bill/#{congress}/#{type}/#{number}/amendments"
        |> CongressGov.paginate("amendments")
        |> Enum.map(&elem(&1, 0))

      _other_congress ->
        []
    end
  end

  # "senate-119-2-249" → {2, 249}
  defp session_roll(external_id) do
    case String.split(external_id, "-") do
      [_body, _congress, session, roll] -> {String.to_integer(session), String.to_integer(roll)}
      _ -> nil
    end
  end

  defp write(links, run_id) do
    Enum.reduce_while(links, :ok, fn {vote, ref, url}, :ok ->
      record = %VoteSubject{
        jurisdiction: "federal",
        body_external_id: "senate",
        session_identifier: vote.session_identifier,
        external_id: vote.external_id,
        subject_ref: ref,
        subject_url: url
      }

      case Ingest.write(record, run_id) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
