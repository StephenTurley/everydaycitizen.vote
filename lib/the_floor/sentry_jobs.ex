defmodule TheFloor.SentryJobs do
  @moduledoc """
  Which failed background jobs become Sentry issues. A transient source failure
  (a dropped connection, a timeout, HTTP 429 or 5xx) is retried by Oban and
  usually goes through, so it is reported only when the last attempt fails.
  Every other error is reported at once.

  Wired as the Oban integration's `should_report_error_callback`
  (config/runtime.exs).
  """

  @spec report_error?(module(), Oban.Job.t()) :: boolean()
  def report_error?(_worker, %Oban.Job{} = job) do
    job.attempt >= job.max_attempts or not transient?(reason(job))
  end

  defp reason(%Oban.Job{unsaved_error: %{reason: %Oban.PerformError{reason: reason}}}), do: reason
  defp reason(%Oban.Job{unsaved_error: %{reason: reason}}), do: reason
  defp reason(_job), do: nil

  defp transient?(%Req.TransportError{}), do: true
  defp transient?(%Mint.TransportError{}), do: true
  defp transient?({:http_status, status}) when status == 429 or status >= 500, do: true
  defp transient?(_reason), do: false
end
