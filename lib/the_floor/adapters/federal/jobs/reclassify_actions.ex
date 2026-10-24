defmodule TheFloor.Adapters.Federal.Jobs.ReclassifyActions do
  @moduledoc """
  Classifies every stored action again with the current `ActionClassifier`
  rules and saves the ones that changed. Run by name after the rules change.
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  alias TheFloor.Adapters.Federal.{ActionClassifier, Job}
  alias TheFloor.Legislation

  @page 5000

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Job.run("reclassify_actions", fn _run_id, _cursor -> {:ok, %{"changed" => pass(0, 0)}} end)
  end

  defp pass(after_id, changed) do
    case Legislation.actions_page("federal", after_id, @page) do
      [] ->
        changed

      page ->
        changes =
          for a <- page,
              # a generator, not `new = ...`: in `for` a nil binding is a filter
              new <- [ActionClassifier.classify(%{"text" => a.description, "type" => a.raw_type})],
              new != a.classification,
              do: {a.id, new}

        :ok = Legislation.update_action_classifications(changes)
        pass(List.last(page).id, changed + length(changes))
    end
  end
end
