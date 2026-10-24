defmodule EverydayCitizen.Jobs.SummarizeSubject do
  @moduledoc """
  Writes a bill's executive summary or a rep's week summary (queued by
  `EverydayCitizen.Summaries.request_ai/3` when someone views it), stores it and
  broadcasts `{:ai_summary, kind, subject, {:ok, text} | {:error, reason}}` to
  the pages showing it. Unique per subject for as long as a job is pending or
  running (a long bill's parts can take more than ten minutes), so many viewers
  cost one summary.
  """
  use Oban.Worker,
    queue: :summaries,
    max_attempts: 3,
    unique: [
      keys: [:kind, :subject, :prompt_version],
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.{Inputs, Writer}

  @kinds %{"bill" => :bill, "rep_week" => :rep_week}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind, "subject" => subject}} = job) do
    with {:ok, kind_atom} <- Map.fetch(@kinds, kind),
         input when is_binary(input) <- Inputs.input(kind, subject) do
      case Summaries.get_ai(kind_atom, subject, input) do
        nil -> write(job, kind, kind_atom, subject, input)
        summary -> broadcast(kind, subject, {:ok, summary.summary})
      end
    else
      _nothing_to_summarize -> :ok
    end
  end

  defp write(job, kind, kind_atom, subject, input) do
    case Writer.write(kind_atom, input) do
      {:ok, result} ->
        {:ok, summary} = Summaries.put_ai(kind_atom, subject, input, result)
        broadcast(kind, subject, {:ok, summary.summary})

      {:error, :paused} ->
        broadcast(kind, subject, {:error, :paused})
        {:cancel, :paused}

      # cut off even with twice the room: another attempt would pay for the same
      {:error, :truncated} ->
        broadcast(kind, subject, {:error, :unavailable})
        {:cancel, :truncated}

      {:error, reason} ->
        if job.attempt >= job.max_attempts, do: broadcast(kind, subject, {:error, :unavailable})
        {:error, reason}
    end
  end

  defp broadcast(kind, subject, result) do
    Phoenix.PubSub.broadcast(
      EverydayCitizen.PubSub,
      Summaries.ai_topic(kind, subject),
      {:ai_summary, kind, subject, result}
    )
  end
end
