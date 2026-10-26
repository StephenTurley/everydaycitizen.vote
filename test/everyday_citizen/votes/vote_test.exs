defmodule EverydayCitizen.Votes.VoteTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Votes.Vote

  test "order_key sorts by date, then time, a vote with no time first on its day" do
    votes = [
      %Vote{external_id: "late", voted_on: ~D[2026-01-20], voted_at: ~U[2026-01-20 23:00:00Z]},
      %Vote{external_id: "next-day", voted_on: ~D[2026-01-21], voted_at: nil},
      %Vote{external_id: "untimed", voted_on: ~D[2026-01-20], voted_at: nil},
      %Vote{external_id: "early", voted_on: ~D[2026-01-20], voted_at: ~U[2026-01-20 15:00:00Z]}
    ]

    assert votes |> Enum.sort_by(&Vote.order_key/1) |> Enum.map(& &1.external_id) ==
             ["untimed", "early", "late", "next-day"]
  end
end
