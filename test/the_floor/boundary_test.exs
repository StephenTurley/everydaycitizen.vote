defmodule TheFloor.BoundaryTest do
  use ExUnit.Case, async: true

  @federal_dir "lib/the_floor/adapters/federal"
  @forbidden ~r/\b(congress|bioguide|senate|house|lis_member|crs)\b/i

  test "no federal concepts outside the federal adapter" do
    offenders =
      "lib/**/*.ex"
      |> Path.wildcard()
      |> Enum.reject(&String.starts_with?(&1, @federal_dir <> "/"))
      |> Enum.filter(fn path -> File.read!(path) =~ @forbidden end)

    assert offenders == []
  end
end
