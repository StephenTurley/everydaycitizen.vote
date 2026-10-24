defmodule EverydayCitizen.Ingest.CoverageTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest.Coverage

  describe "record/5 tolerance" do
    test "within tolerance below expected passes" do
      assert {:ok, %{passed: true}} = Coverage.record(nil, "a", 1000, 995, 0.005)
    end

    test "below the tolerance floor fails" do
      assert {:ok, %{passed: false}} = Coverage.record(nil, "a", 1000, 994, 0.005)
    end

    test "above expected fails" do
      assert {:ok, %{passed: false}} = Coverage.record(nil, "a", 1000, 1001, 0.005)
    end

    test "zero tolerance requires equality" do
      assert {:ok, %{passed: true}} = Coverage.record(nil, "a", 10, 10, 0)
      assert {:ok, %{passed: false}} = Coverage.record(nil, "a", 10, 9, 0)
    end
  end

  test "record_failure/4 stores a failed check with no expected count" do
    assert {:ok, check} = Coverage.record_failure(nil, "x", 0, "boom")
    assert check.passed == false
    assert check.expected == nil
    assert check.error == "boom"
  end

  test "latest/0 returns the newest row per name" do
    {:ok, _} = Coverage.record(nil, "a", 10, 5, 0)
    {:ok, _} = Coverage.record(nil, "a", 10, 10, 0)
    {:ok, _} = Coverage.record(nil, "b", 3, 3, 0)

    latest = Coverage.latest()
    assert Enum.map(latest, & &1.name) == ["a", "b"]
    assert Enum.find(latest, &(&1.name == "a")).passed
  end
end
