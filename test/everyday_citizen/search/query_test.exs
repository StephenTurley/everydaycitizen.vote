defmodule EverydayCitizen.Search.QueryTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Search.Query

  test "addresses and ZIP codes are recognized" do
    for q <- [
          "43215",
          "43215-1234",
          "123 Main St",
          "1600 Pennsylvania Avenue NW, Washington",
          "12 N High",
          "4B Elm Court",
          "77 Route 9"
        ],
        do: assert(Query.classify(q) == :address, q)
  end

  test "bill numbers, names, phrases and bare numbers are searches" do
    assert {:search, %{id_key: "hr22"}} = Query.classify("H.R. 22")
    assert {:search, %{id_key: "hr22"}} = Query.classify("hr22")
    assert {:search, %{id_key: "hres1131"}} = Query.classify("H.Res. 1131")
    assert {:search, %{id_key: nil, key: "save"}} = Query.classify("SAVE Act")
    assert {:search, %{number: "22", id_key: nil}} = Query.classify("22")
    assert {:search, %{text: "22 states"}} = Query.classify(" 22   states ")
    assert {:search, %{text: "daylight saving time"}} = Query.classify("daylight saving time")
  end

  test "empty and one-character queries are empty" do
    for q <- [nil, "", "   ", "a"], do: assert(Query.classify(q) == :empty)
  end

  test "text is capped at 200 characters" do
    {:search, %{text: text}} = Query.classify(String.duplicate("a", 300))
    assert String.length(text) == 200
  end
end

defmodule EverydayCitizen.Search.QueryKeyTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Search.Query

  test "the Elixir name key matches the database's" do
    for s <- [
          "SAVE Act",
          "Laken Riley Act of 2025",
          "  H.R. 22 — the SAVE act!",
          "Ünïcode Act",
          "Zoë Lofgren",
          "ÉCOLE"
        ] do
      assert Query.name_key(s) == hd(hd(Repo.query!("select ec_name_key($1)", [s]).rows)), s
    end
  end
end
