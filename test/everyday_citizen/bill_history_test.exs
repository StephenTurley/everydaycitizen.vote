defmodule EverydayCitizen.BillHistoryTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.BillHistory
  alias EverydayCitizen.Legislation

  import EverydayCitizen.HistoryFixtures

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    %{bill: three_versions!()}
  end

  defp short,
    do:
      section("1.", "Short title", [
        %{"level" => 0, "text" => "This Act may be cited as the Stop Insider Trading Act."}
      ])

  test "versions come oldest first", %{bill: bill} do
    assert Enum.map(BillHistory.versions(bill), & &1.code) == ["ih", "rh", "eh"]
  end

  test "each section of a version says where it came from", %{bill: bill} do
    assert %{
             0 => %{status: :original, added_in: "ih", changed_in: []},
             1 => %{status: :changed, added_in: "ih", changed_in: ["rh"]},
             2 => %{status: :added, added_in: "eh", changed_in: []}
           } = BillHistory.origins(bill, "eh")

    # read at the committee version, the voter ID section doesn't exist yet
    assert map_size(BillHistory.origins(bill, "rh")) == 2
  end

  test "a changed section compares against the wording before its last change", %{bill: bill} do
    %{from: "ih", to: "rh", paragraphs: paragraphs} = BillHistory.comparison(bill, "eh", 1)
    ops = List.flatten(paragraphs)

    assert {:del, "— (i) "} in ops
    assert {:ins, "."} in ops
    assert Enum.any?(ops, &match?({:del, "; and"}, &1))
    # the unchanged paragraph after the change is kept as is
    assert [{:eq, "(B) Exclusion. The term covered investment does not include—"}] in paragraphs
  end

  test "unchanged and added sections have no comparison", %{bill: bill} do
    assert BillHistory.comparison(bill, "eh", 0) == nil
    assert BillHistory.comparison(bill, "eh", 2) == nil
  end

  test "a bill with one version with sections has no origins", %{bill: bill} do
    other = Legislation.get_bill("federal", "119-s-5")
    assert other.id == bill.id
    lone = %{bill | id: -1}
    assert BillHistory.origins(lone, "ih") == %{}
  end

  test "sections sharing a heading are told apart by order", %{bill: bill} do
    dup = fn text -> section(nil, "Definitions", [%{"level" => 0, "text" => text}]) end
    version!(bill, "pcs", ~D[2026-08-06], [short(), dup.("First."), dup.("Second, changed.")])

    version!(bill, "rfs", ~D[2026-08-07], [
      short(),
      dup.("First."),
      dup.("Second, changed again.")
    ])

    origins = BillHistory.origins(bill, "rfs")
    assert origins[1].changed_in == []
    assert origins[2].changed_in == ["rfs"]
  end

  test "clauses are compared one by one however the text was split into paragraphs", %{bill: bill} do
    one_block = fn text -> [%{"level" => 0, "text" => text}] end

    version!(bill, "pcs", ~D[2026-08-06], [
      short(),
      section("2.", "Definitions", [
        %{"level" => 0, "text" => "In this subchapter—"},
        %{
          "level" => 1,
          "enum" => "(1)",
          "heading" => "Covered individual",
          "text" => "The term covered individual means a Member."
        },
        %{
          "level" => 1,
          "enum" => "(2)",
          "heading" => "Occupation",
          "text" => "The rules do not apply to a spouse's job."
        },
        %{
          "level" => 1,
          "enum" => "(3)",
          "heading" => "Public company",
          "text" => "The term public company means an issuer."
        }
      ])
    ])

    # the same clauses run together in one paragraph, a colon for the dash, and (2) struck
    version!(bill, "rfs", ~D[2026-08-07], [
      short(),
      section(
        "2.",
        "Definitions",
        one_block.(
          "In this subchapter: (1) Covered individual. The term covered individual means a Member. (3) Public company. The term public company means an issuer."
        )
      )
    ])

    %{paragraphs: paragraphs} = BillHistory.comparison(bill, "rfs", 1)

    changed = Enum.reject(paragraphs, &match?([{:eq, _}], &1))
    assert [[{:del, "(2) Occupation. The rules do not apply to a spouse's job."}]] = changed
  end

  test "a clause run straight onto the word before still starts its own clause; citations don't",
       %{bill: bill} do
    one = fn text -> [section("2.", "Definitions", [%{"level" => 0, "text" => text}])] end

    version!(bill, "pcs", ~D[2026-08-06], [
      short()
      | one.(
          "Restrictions on investments(a)Conduct. No purchase, see section 13104(f)(8). (b)Notice. Old notice."
        )
    ])

    version!(bill, "rfs", ~D[2026-08-07], [
      short()
      | one.(
          "Restrictions on investments(a)Conduct. No purchase, see section 13104(f)(8). (b)Notice. New notice."
        )
    ])

    %{paragraphs: paragraphs} = BillHistory.comparison(bill, "rfs", 1)
    assert [{:eq, "(a)Conduct. No purchase, see section 13104(f)(8)."}] in paragraphs
    assert Enum.any?(paragraphs, &({:del, "Old"} in &1))
  end

  test "a huge changed passage is compared without word marks, quickly", %{bill: bill} do
    words = fn seed -> Enum.map_join(1..6000, " ", &"w#{rem(&1 * seed, 997)}") end
    one = fn text -> [section("2.", "Big", [%{"level" => 0, "text" => text}])] end
    version!(bill, "pcs", ~D[2026-08-06], [short() | one.(words.(7))])
    version!(bill, "rfs", ~D[2026-08-07], [short() | one.(words.(11))])

    {micros, %{paragraphs: paragraphs}} =
      :timer.tc(fn -> BillHistory.comparison(bill, "rfs", 1) end)

    assert micros < 1_000_000
    assert [[{:del, _}], [{:ins, _}]] = paragraphs
  end

  test "sections sharing a heading are matched by heading and number, so an insert doesn't shift them",
       %{bill: bill} do
    defs = fn enum, text -> section(enum, "Definitions", [%{"level" => 0, "text" => text}]) end
    version!(bill, "pcs", ~D[2026-08-06], [short(), defs.("101.", "A."), defs.("201.", "B.")])

    version!(bill, "rfs", ~D[2026-08-07], [
      short(),
      defs.("101.", "A."),
      defs.("150.", "New."),
      defs.("201.", "B.")
    ])

    origins = BillHistory.origins(bill, "rfs")
    assert origins[1].status == :added and origins[1].added_in == "pcs"
    assert origins[2] == %{status: :added, added_in: "rfs", changed_in: []}
    assert origins[3].changed_in == []
  end

  test "amending text splits at its own clauses, lowercase too, but not inside citations", %{
    bill: bill
  } do
    para = fn text -> %{"level" => 0, "text" => text} end

    amend = fn last ->
      [
        section("2.", "Amendments", [
          para.(
            "Section 5 is amended— (1) in subsection (b)(2), by striking (EPA) and inserting Agency; and (2) #{last}"
          )
        ])
      ]
    end

    version!(bill, "pcs", ~D[2026-08-06], [short() | amend.("by adding at the end a rule.")])
    version!(bill, "rfs", ~D[2026-08-07], [short() | amend.("by adding at the end a new rule.")])

    %{paragraphs: paragraphs} = BillHistory.comparison(bill, "rfs", 1)
    assert [{:eq, "Section 5 is amended—"}] in paragraphs

    assert [{:eq, "(1) in subsection (b)(2), by striking (EPA) and inserting Agency; and"}] in paragraphs
  end
end
