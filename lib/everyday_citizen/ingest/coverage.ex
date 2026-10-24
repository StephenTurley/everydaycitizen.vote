defmodule EverydayCitizen.Ingest.Coverage do
  @moduledoc """
  Coverage checks compare what we stored with what the source reports (spec 7.1).
  A check passes iff `actual <= expected` and
  `actual >= floor(expected * (1 - tolerance))`: we may lag the source by the
  tolerance (records created during a run) but never exceed it.

  When the source count cannot be fetched the check is recorded as failed with
  `expected: nil` and an error note; absence of evidence is not a pass.
  """
  import Ecto.Query

  alias EverydayCitizen.Ingest.CoverageCheck
  alias EverydayCitizen.Repo

  @spec record(integer() | nil, String.t(), integer(), integer(), number()) ::
          {:ok, CoverageCheck.t()}
  def record(run_id, name, expected, actual, tolerance) do
    insert(%CoverageCheck{
      ingest_run_id: run_id,
      name: name,
      expected: expected,
      actual: actual,
      tolerance: tolerance * 1.0,
      passed: passes?(expected, actual, tolerance)
    })
  end

  @doc "Records a failed check whose expected count could not be determined."
  @spec record_failure(integer() | nil, String.t(), number(), String.t()) ::
          {:ok, CoverageCheck.t()}
  def record_failure(run_id, name, tolerance, error) do
    insert(%CoverageCheck{
      ingest_run_id: run_id,
      name: name,
      tolerance: tolerance * 1.0,
      passed: false,
      error: error
    })
  end

  @doc "The most recent row for each check name, ordered by name."
  @spec latest() :: [CoverageCheck.t()]
  def latest do
    CoverageCheck
    |> distinct([c], c.name)
    |> order_by([c], asc: c.name, desc: c.id)
    |> Repo.all()
  end

  defp passes?(expected, actual, tolerance) do
    # Rounding first keeps float noise (e.g. 1000 * 0.995) from moving the floor.
    floor = trunc(Float.floor(Float.round(expected * (1 - tolerance) * 1.0, 6)))
    actual <= expected and actual >= floor
  end

  defp insert(check), do: {:ok, Repo.insert!(check)}

  @doc "Formats checks as `name expected actual PASS|FAIL [error]` rows."
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
