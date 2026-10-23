defmodule TheFloor.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :the_floor

  alias TheFloor.Ingest.Coverage
  alias TheFloor.Ingest.Jobs

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Enqueues the ingest jobs (all, or one by name) in the running app, which
  then runs them. The release counterpart of `mix the_floor.ingest`:

      bin/the_floor rpc 'TheFloor.Release.ingest()'
      bin/the_floor rpc 'TheFloor.Release.ingest("bills")'
  """
  def ingest(name \\ nil) do
    case Jobs.select(name) do
      {:ok, jobs} ->
        for {name, job} <- Jobs.enqueue(jobs), do: IO.puts("enqueued #{name} (job #{job.id})")
        :ok

      {:error, message} ->
        raise ArgumentError, message
    end
  end

  @doc """
  Prints the latest coverage checks from the running app and returns `:ok`, or
  `{:error, failed_count}` if any failed. The release counterpart of
  `mix the_floor.coverage`:

      bin/the_floor rpc 'TheFloor.Release.coverage()'
  """
  def coverage do
    case Coverage.latest() do
      [] ->
        IO.puts(~s|no coverage checks recorded; run TheFloor.Release.ingest("coverage")|)
        {:error, :no_checks}

      checks ->
        IO.puts(Coverage.format_rows(checks))

        case Enum.count(checks, &(not &1.passed)) do
          0 -> :ok
          failed -> {:error, failed}
        end
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
