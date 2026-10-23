defmodule TheFloor.Adapters.Federal.BillIdTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.BillId

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
end
