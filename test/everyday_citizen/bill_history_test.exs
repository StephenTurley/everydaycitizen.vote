defmodule EverydayCitizen.BillHistoryTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.BillHistory
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation

  @src Records.SourceRef.new("https://x.test/v", "v")

  @old_def [
    %{
      "level" => 3,
      "enum" => "(A)",
      "heading" => "In general",
      "text" => "The term covered investment—"
    },
    %{
      "level" => 4,
      "enum" => "(i)",
      "heading" => nil,
      "text" =>
        "means a security issued by a publicly traded company or any comparable economic interest acquired through synthetic means, such as the use of a derivative, including an option, warrant, or other similar means; and"
    }
  ]
  @new_def [
    %{
      "level" => 3,
      "enum" => "(A)",
      "heading" => "In general",
      "text" =>
        "The term covered investment means a security issued by a publicly traded company or any comparable economic interest acquired through synthetic means, such as the use of a derivative, including an option, warrant, or other similar means."
    }
  ]

  defp section(enum, heading, blocks),
    do: %{"kind" => "section", "enum" => enum, "heading" => heading, "blocks" => blocks}

  defp short,
    do:
      section("1.", "Short title", [
        %{"level" => 0, "text" => "This Act may be cited as the Stop Insider Trading Act."}
      ])

  defp tail,
    do: [
      %{
        "level" => 3,
        "enum" => "(B)",
        "heading" => "Exclusion",
        "text" => "The term covered investment does not include—"
      }
    ]

  defp voter_id,
    do:
      section("3.", "Requiring voters to provide photo identification", [
        %{
          "level" => 1,
          "enum" => "(a)",
          "heading" => "Requirement",
          "text" => "A valid photo identification is required."
        }
      ])

  defp version!(bill, code, date, sections) do
    {:ok, _} =
      Ingest.write(
        %Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: bill.external_id,
          code: code,
          classification: code,
          date: date,
          source: @src
        },
        nil
      )

    if sections,
      do: :ok = Legislation.put_sections(Legislation.get_version(bill, code).id, sections, 2)
  end

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    bill = Legislation.get_bill("federal", "119-s-5")

    version!(bill, "ih", ~D[2026-01-12], [
      short(),
      section("2.", "Restrictions on covered investments", @old_def ++ tail())
    ])

    version!(bill, "rh", ~D[2026-02-03], [
      short(),
      section("2.", "Restrictions on covered investments", @new_def ++ tail())
    ])

    # whitespace-only differences are not changes
    eh_short =
      section("1.", "Short title", [
        %{"level" => 0, "text" => "This Act may be cited as   the Stop Insider Trading Act."}
      ])

    version!(bill, "eh", ~D[2026-07-22], [
      eh_short,
      section("2.", "Restrictions on covered investments", @new_def ++ tail()),
      voter_id()
    ])

    %{bill: bill}
  end

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
end
