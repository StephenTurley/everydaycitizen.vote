defmodule EverydayCitizen.Adapters.Federal.JobsTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Jobs
  alias EverydayCitizen.Ingest.Coverage
  alias EverydayCitizen.Ingest.CoverageCheck

  test "the registry lists unique names with loadable workers, coverage last" do
    jobs = Jobs.all()
    names = Enum.map(jobs, &elem(&1, 0))

    assert names == Enum.uniq(names)
    assert List.last(names) == "coverage"
    assert hd(names) == "congress"

    for {_name, worker, args} <- jobs do
      assert Code.ensure_loaded?(worker)
      assert is_map(args)
    end
  end

  test "the configured adapters include the registry" do
    assert Jobs in Application.fetch_env!(:everyday_citizen, :ingest_adapters)
  end

  test "coverage output shows PASS, FAIL and a missing expected count" do
    out =
      Coverage.format_rows([
        %CoverageCheck{name: "a", expected: 10, actual: 10, passed: true},
        %CoverageCheck{name: "longer", expected: 10, actual: 3, passed: false},
        %CoverageCheck{name: "c", expected: nil, actual: 4, passed: false, error: "403"}
      ])

    assert out =~ ~r/^a\s+10\s+10\s+PASS$/m
    assert out =~ ~r/^longer\s+10\s+3\s+FAIL$/m
    assert out =~ ~r/^c\s+-\s+4\s+FAIL\s+403$/m
  end
end
