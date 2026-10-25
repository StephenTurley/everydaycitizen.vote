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

  test "unusual spaces count as spaces, so an address with them is still an address" do
    for q <- [
          "123\u00A0Main\u00A0St",
          "123\u00A0N\u00A0Main",
          "50309\u00A0",
          "\u00A050309",
          "50309\u200B",
          "\uFEFF50309",
          "123\u2003Main\u2003St"
        ],
        do: assert(Query.classify(q) == :address, inspect(q))
  end

  test "a ZIP code anywhere in the query makes it an address" do
    for q <- ["Des Moines IA 50309", "my zip 50309", "50309-1234 Des Moines"],
        do: assert(Query.classify(q) == :address, q)
  end

  test "a PO box is an address" do
    for q <- ["PO Box 12", "P.O. Box 12", "p o box 12", "po box 7"],
        do: assert(Query.classify(q) == :address, q)
  end

  test "a five-digit bill number is a search, not a ZIP code" do
    assert {:search, %{id_key: "hr10000"}} = Query.classify("hr10000")
    assert {:search, %{id_key: "hr10000"}} = Query.classify("H.R. 10000")
    assert {:search, %{id_key: "hres10000"}} = Query.classify("H. Res. 10000")
  end

  test "numbers beside ordinary words stay searches" do
    for q <- ["1 way forward", "22 ways", "12 N", "22 states", "H.R. 22", "hr22", "2025 tax"],
        do: assert({:search, _} = Query.classify(q), q)
  end

  test "the search text has its spaces normalized" do
    assert {:search, %{text: "daylight saving time"}} =
             Query.classify("\u00A0daylight\u200B\u00A0saving\u2003time\uFEFF")
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
