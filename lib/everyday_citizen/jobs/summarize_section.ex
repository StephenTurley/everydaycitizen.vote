defmodule EverydayCitizen.Jobs.SummarizeSection do
  @moduledoc """
  Writes the plain-English summary of one section (queued by
  `EverydayCitizen.Summaries.request/3` when someone opens it) and broadcasts it
  to the pages showing that section: `{:section_summary, index, {:ok, text}}`,
  or `{:error, :unavailable}` once the last attempt fails. Unique per section
  and prompt version, so a section opened by many people at once costs one call.
  """
  use Oban.Worker,
    queue: :summaries,
    max_attempts: 3,
    unique: [
      keys: [:version_id, :index, :prompt_version],
      period: 300,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query

  alias EverydayCitizen.Legislation.BillVersion
  alias EverydayCitizen.{Repo, Summaries}
  alias EverydayCitizen.Summaries.Claude

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"version_id" => version_id, "index" => index}} = job) do
    case section(version_id, index) do
      %{"kind" => "section"} = section -> summarize(job, version_id, index, section)
      _not_a_section -> :ok
    end
  end

  defp summarize(job, version_id, index, section) do
    text = Summaries.section_text(section)

    cond do
      summary = Summaries.get(version_id, index, text) ->
        broadcast(version_id, index, {:ok, summary.summary})

      # jobs queued before the day's budget ran out must not overrun it
      Summaries.over_budget?() ->
        broadcast(version_id, index, {:error, :paused})
        {:cancel, :paused}

      true ->
        write(job, version_id, index, text)
    end
  end

  defp write(job, version_id, index, text) do
    case Claude.summarize(text) do
      {:ok, result} ->
        :ok = Summaries.record_usage(:section, result)
        {:ok, summary} = Summaries.put(version_id, index, text, result)
        broadcast(version_id, index, {:ok, summary.summary})

      {:error, reason} ->
        if job.attempt >= job.max_attempts,
          do: broadcast(version_id, index, {:error, :unavailable})

        {:error, reason}
    end
  end

  defp section(version_id, index) do
    sections = Repo.one(from v in BillVersion, where: v.id == ^version_id, select: v.sections)
    sections && Enum.at(sections, index)
  end

  defp broadcast(version_id, index, result) do
    Phoenix.PubSub.broadcast(
      EverydayCitizen.PubSub,
      Summaries.topic(version_id, index),
      {:section_summary, index, result}
    )
  end
end
