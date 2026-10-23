defmodule TheFloor.SentryJobsTest do
  use ExUnit.Case, async: true

  alias TheFloor.SentryJobs

  defp job(attempt, reason) do
    %Oban.Job{
      attempt: attempt,
      max_attempts: 3,
      unsaved_error: %{reason: %Oban.PerformError{reason: reason}}
    }
  end

  test "a transient failure is reported only on the last attempt" do
    for reason <- [
          %Req.TransportError{reason: :timeout},
          {:http_status, 503},
          {:http_status, 429}
        ] do
      refute SentryJobs.report_error?(Worker, job(1, reason)), inspect(reason)
      assert SentryJobs.report_error?(Worker, job(3, reason)), inspect(reason)
    end
  end

  test "any other failure is reported at once" do
    assert SentryJobs.report_error?(Worker, job(1, {:missing_prerequisite, :session}))
    assert SentryJobs.report_error?(Worker, job(1, {:http_status, 404}))
  end

  test "a raised exception is reported at once" do
    job = %Oban.Job{attempt: 1, max_attempts: 3, unsaved_error: %{reason: %RuntimeError{}}}
    assert SentryJobs.report_error?(Worker, job)
  end
end
