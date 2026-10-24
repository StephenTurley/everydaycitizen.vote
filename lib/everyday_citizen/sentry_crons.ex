defmodule EverydayCitizen.SentryCrons do
  @moduledoc """
  Reports one scheduled job's runs to Sentry's Crons page, which flags a run
  that failed, ran long or never came. The plan allows one monitor, so a job
  opts in by wrapping its work in `monitor/2` (the Oban integration's own cron
  reporting would create one per scheduled worker). Only runs started by the
  schedule report; a run enqueued by hand does not. A job that snoozes before
  calling `monitor/2` reports once, when it runs.
  """

  @doc """
  Runs `fun` for `job`, reporting its start and its result (`:ok`, or failed on
  `{:error, _}` or a raise) when the schedule started the job. Returns `fun`'s
  result. Options: `:slug` (default from the worker's name; pass one to keep
  an existing monitor) and `:send` (the check-in function, for tests).
  """
  @spec monitor(Oban.Job.t(), (-> result), keyword()) :: result when result: term()
  def monitor(job, fun, opts \\ [])

  def monitor(%Oban.Job{meta: %{"cron" => true, "cron_expr" => expr} = meta} = job, fun, opts) do
    send = Keyword.get(opts, :send, &Sentry.capture_check_in/1)
    slug = Keyword.get_lazy(opts, :slug, fn -> slug(job.worker) end)

    monitor_config =
      [schedule: [type: :crontab, value: expr]] ++
        if(tz = meta["cron_tz"], do: [timezone: tz], else: [])

    id =
      case send.(status: :in_progress, monitor_slug: slug, monitor_config: monitor_config) do
        {:ok, id} -> [check_in_id: id]
        _ignored -> []
      end

    started = System.monotonic_time(:millisecond)
    finish = &send.(id ++ [status: &1, monitor_slug: slug, duration: seconds_since(started)])

    try do
      result = fun.()
      finish.(if match?({:error, _}, result), do: :error, else: :ok)
      result
    rescue
      exception ->
        finish.(:error)
        reraise exception, __STACKTRACE__
    end
  end

  def monitor(%Oban.Job{}, fun, _opts), do: fun.()

  defp seconds_since(started), do: (System.monotonic_time(:millisecond) - started) / 1000

  # MyApp.SomeWorker -> "my-app-some-worker", as the Oban integration names them
  defp slug(worker) do
    worker
    |> String.split(".")
    |> Enum.map_join("-", &(&1 |> Macro.underscore() |> String.replace("_", "-")))
    |> String.slice(0, 50)
  end
end
