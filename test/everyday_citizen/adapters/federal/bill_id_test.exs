defmodule EverydayCitizen.Adapters.Federal.BillIdTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Adapters.Federal.BillId

  test "web_url/1 is the bill's page for people on Congress.gov" do
    assert BillId.web_url("119-s-5") ==
             "https://www.congress.gov/bill/119th-congress/senate-bill/5"

    assert BillId.web_url("119-hconres-3") ==
             "https://www.congress.gov/bill/119th-congress/house-concurrent-resolution/3"

    for {type, slug} <- [
          {"hr", "house-bill"},
          {"hres", "house-resolution"},
          {"sres", "senate-resolution"},
          {"hjres", "house-joint-resolution"},
          {"sjres", "senate-joint-resolution"},
          {"sconres", "senate-concurrent-resolution"}
        ],
        do: assert(BillId.web_url("119-#{type}-7") =~ "/119th-congress/#{slug}/7")

    for {congress, ordinal} <- [
          {101, "101st"},
          {102, "102nd"},
          {103, "103rd"},
          {111, "111th"},
          {112, "112th"},
          {113, "113th"},
          {121, "121st"}
        ],
        do: assert(BillId.web_url("#{congress}-hr-1") =~ "/#{ordinal}-congress/")

    assert BillId.web_url("not-an-id") == nil
  end

  test "external_id/3 lowercases the type" do
    assert BillId.external_id(119, "HJRES", 5) == "119-hjres-5"
    assert BillId.external_id(119, "HR", "1234") == "119-hr-1234"
  end

  test "identifier/2 and classification/1 per type" do
    table = [
      {"HR", "H.R. 1", "bill"},
      {"S", "S. 1", "bill"},
      {"HRES", "H.Res. 1", "resolution"},
      {"SRES", "S.Res. 1", "resolution"},
      {"HJRES", "H.J.Res. 1", "joint_resolution"},
      {"SJRES", "S.J.Res. 1", "joint_resolution"},
      {"HCONRES", "H.Con.Res. 1", "concurrent_resolution"},
      {"SCONRES", "S.Con.Res. 1", "concurrent_resolution"}
    ]

    for {code, identifier, classification} <- table do
      assert BillId.identifier(code, 1) == identifier
      assert BillId.classification(code) == classification
    end
  end

  test "from_label/2 parses display labels" do
    assert BillId.from_label("H.R. 1234", 119) == "119-hr-1234"
    assert BillId.from_label("H.R.1234", 119) == "119-hr-1234"
    assert BillId.from_label("S. 5", 119) == "119-s-5"
    assert BillId.from_label("S.J.Res. 12", 119) == "119-sjres-12"
    assert BillId.from_label("H. Con. Res. 3", 119) == "119-hconres-3"
    assert BillId.from_label("h.res. 7", 118) == "118-hres-7"
    assert BillId.from_label("S.Res. 9", 119) == "119-sres-9"
  end

  test "from_label/2 returns nil for non-bill labels" do
    assert BillId.from_label("PN 123", 119) == nil
    assert BillId.from_label("", 119) == nil
    assert BillId.from_label(nil, 119) == nil
    assert BillId.from_label("H.R. abc", 119) == nil
  end

  test "scan/2 finds labels in free text, in order, deduplicated" do
    text = "Taking up S. 5, H.R. 1234 and H.Con.Res. 3; S.5 again. Not U.S. 5 or PN 9."
    assert BillId.scan(text, 119) == ["119-s-5", "119-hr-1234", "119-hconres-3"]
    assert BillId.scan("nothing here", 119) == []
    assert BillId.scan(nil, 119) == []
  end
end
