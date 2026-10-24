defmodule EverydayCitizen.Adapters.Federal.Normalize.CongressTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Normalize.Congress
  alias EverydayCitizen.Ingest.Records.{Body, Jurisdiction, LegislativeSession, SourceRef}

  @fixture "test/support/fixtures/federal/congress_gov/congress_119.json"

  setup do
    json = @fixture |> File.read!() |> Jason.decode!()
    source = SourceRef.new("https://api.congress.gov/v3/congress/119", "x")
    {:ok, records: Congress.records(json, source), source: source}
  end

  test "produces the jurisdiction", %{records: records, source: source} do
    assert [
             %Jurisdiction{
               key: "federal",
               name: "United States Congress",
               classification: "federal",
               source: ^source
             }
           ] =
             Enum.filter(records, &is_struct(&1, Jurisdiction))
  end

  test "produces the legislature and two chambers", %{records: records} do
    bodies =
      for %Body{} = b <- records, do: {b.external_id, b.classification, b.parent_external_id}

    assert bodies == [
             {"congress", "legislature", nil},
             {"house", "chamber", "congress"},
             {"senate", "chamber", "congress"}
           ]
  end

  test "produces the congress session and sub-sessions with dates", %{records: records} do
    sessions =
      for %LegislativeSession{} = s <- records,
          do: {s.identifier, s.parent_identifier, s.start_date, s.end_date}

    assert sessions == [
             {"119", nil, ~D[2025-01-03], nil},
             {"119-1", "119", ~D[2025-01-03], ~D[2026-01-03]},
             {"119-2", "119", ~D[2026-01-03], nil}
           ]
  end

  test "writes in dependency order", %{records: records} do
    kinds = Enum.map(records, & &1.__struct__)

    assert kinds == [
             Jurisdiction,
             Body,
             Body,
             Body,
             LegislativeSession,
             LegislativeSession,
             LegislativeSession
           ]
  end
end
