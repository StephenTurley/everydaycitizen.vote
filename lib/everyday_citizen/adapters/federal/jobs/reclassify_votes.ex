defmodule EverydayCitizen.Adapters.Federal.Jobs.ReclassifyVotes do
  @moduledoc """
  Types every stored vote again from its question with the current
  `VoteClassifier` rules and saves the ones that changed. Run by name.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias EverydayCitizen.Adapters.Federal.{Job, VoteClassifier}
  alias EverydayCitizen.Votes

  @page 5000

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Job.run("reclassify_votes", fn _run_id, _cursor -> {:ok, %{"changed" => pass(0, 0)}} end)
  end

  defp pass(after_id, changed) do
    case Votes.questions_page("federal", after_id, @page) do
      [] ->
        changed

      page ->
        changes =
          for v <- page,
              new <- [VoteClassifier.classify(v.question)],
              new != v.classification,
              do: {v.id, new}

        :ok = Votes.reclassify(changes)
        pass(List.last(page).id, changed + length(changes))
    end
  end
end
