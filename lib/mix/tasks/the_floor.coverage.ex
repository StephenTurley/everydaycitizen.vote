defmodule Mix.Tasks.TheFloor.Coverage do
  @shortdoc "Prints the latest coverage checks; exits non-zero if any fail"
  @moduledoc """
  Prints the most recent result of every coverage check
  (`name expected actual PASS|FAIL`) and exits with status 1 if any failed.
  A check whose source count could not be fetched shows `-` as expected and
  counts as a failure. Checks are produced by the `coverage` ingest job
  (`mix the_floor.ingest coverage`).
  """
  use Mix.Task

  alias TheFloor.Ingest.Coverage

  @impl Mix.Task
  def run(_args) do
    TheFloor.Ingest.Mix.start_without_workers()

    checks = Coverage.latest()

    if checks == [] do
      Mix.raise("no coverage checks recorded; run: mix the_floor.ingest coverage")
    end

    Mix.shell().info(format_rows(checks))

    case Enum.count(checks, &(not &1.passed)) do
      0 -> :ok
      failed -> Mix.raise("#{failed} coverage check(s) failed")
    end
  end

  @doc false
  def format_rows(checks) do
    rows =
      Enum.map(checks, fn c ->
        [
          c.name,
          show(c.expected),
          show(c.actual),
          if(c.passed, do: "PASS", else: "FAIL"),
          c.error || ""
        ]
      end)

    width = rows |> Enum.map(&(&1 |> hd() |> String.length())) |> Enum.max()

    Enum.map_join(rows, "\n", fn [name, expected, actual, status, error] ->
      line =
        String.pad_trailing(name, width) <>
          "  " <>
          String.pad_leading(expected, 8) <>
          "  " <> String.pad_leading(actual, 8) <> "  " <> status

      String.trim_trailing(if error == "", do: line, else: line <> "  " <> error)
    end)
  end

  defp show(nil), do: "-"
  defp show(n), do: Integer.to_string(n)
end
