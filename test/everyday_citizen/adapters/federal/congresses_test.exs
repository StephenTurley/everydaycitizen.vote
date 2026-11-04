defmodule EverydayCitizen.Adapters.Federal.CongressesTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.Congresses

  test "the sitting congress changes on Jan 3 of odd years" do
    assert Congresses.current(~D[2026-11-04]) == 119
    assert Congresses.current(~D[2027-01-02]) == 119
    assert Congresses.current(~D[2027-01-03]) == 120
    assert Congresses.current(~D[2025-01-02]) == 118
    assert Congresses.current(~D[2029-01-03]) == 121
  end

  test "start_date" do
    assert Congresses.start_date(120) == ~D[2027-01-03]
  end

  test "the previous congress syncs for 30 days" do
    assert Congresses.syncing(~D[2026-11-04]) == [119]
    assert Congresses.syncing(~D[2027-01-03]) == [120, 119]
    assert Congresses.syncing(~D[2027-02-01]) == [120, 119]
    assert Congresses.syncing(~D[2027-02-02]) == [120]
  end

  test "tests pin today from config" do
    assert Congresses.today() == ~D[2026-11-04]
    assert Congresses.current() == 119
  end
end
