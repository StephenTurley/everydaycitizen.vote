defmodule EverydayCitizen.SummariesTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.SectionSummary

  @section %{
    "kind" => "section",
    "enum" => "2.",
    "heading" => "Changes",
    "blocks" => [
      %{
        "level" => 0,
        "enum" => "(a)",
        "heading" => "In general",
        "text" => "Section 5 is amended by adding:"
      },
      %{
        "level" => 0,
        "quote" => [
          %{"level" => 0, "enum" => "6.", "heading" => "New", "text" => "Inserted text."}
        ]
      },
      %{"level" => 1, "enum" => "(1)", "heading" => nil, "text" => "A paragraph."}
    ]
  }

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")

    {:ok, _} =
      EverydayCitizen.Ingest.write(
        %EverydayCitizen.Ingest.Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: "119-s-5",
          code: "is",
          source: source_ref()
        },
        nil
      )

    %{version: EverydayCitizen.Legislation.get_version(bill, "is")}
  end

  defp summary_attrs,
    do: %{
      summary: "It adds a new rule.",
      model: "claude-haiku-5-5",
      input_tokens: 120,
      output_tokens: 30
    }

  test "section_text puts the heading and each block on its own line, quotes marked" do
    text = Summaries.section_text(@section)

    assert text ==
             """
             Sec. 2. Changes
             (a) In general. Section 5 is amended by adding:
             [Inserted into the law:
             6. New. Inserted text.
             ]
             (1) A paragraph.\
             """
  end

  test "a stored summary is found for the same text, and not once the text changes", %{version: v} do
    text = Summaries.section_text(@section)
    assert {:ok, %SectionSummary{}} = Summaries.put(v.id, 1, text, summary_attrs())

    assert %SectionSummary{summary: "It adds a new rule."} = Summaries.get(v.id, 1, text)
    assert Summaries.get(v.id, 1, text <> " changed") == nil
    assert Summaries.get(v.id, 2, text) == nil
  end

  test "storing twice keeps one summary per section and prompt version", %{version: v} do
    text = Summaries.section_text(@section)
    {:ok, _} = Summaries.put(v.id, 1, text, summary_attrs())
    {:ok, _} = Summaries.put(v.id, 1, text, %{summary_attrs() | summary: "Second."})

    assert Repo.aggregate(SectionSummary, :count) == 1
    assert %SectionSummary{summary: "Second."} = Summaries.get(v.id, 1, text)
  end

  test "created_today counts summaries made today", %{version: v} do
    assert Summaries.created_today() == 0
    {:ok, _} = Summaries.put(v.id, 1, "text", summary_attrs())
    assert Summaries.created_today() == 1
  end
end
