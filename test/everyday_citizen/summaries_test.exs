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

  test "get_many finds every current summary for a version in one query", %{version: v} do
    for i <- 1..3, do: {:ok, _} = Summaries.put(v.id, i, "text #{i}", summary_attrs())

    test = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler,
      [:everyday_citizen, :repo, :query],
      fn _, _, meta, _ ->
        if meta.source == "section_summaries", do: send(test, :summary_query)
      end,
      nil
    )

    found =
      Summaries.get_many(v.id, [{1, "text 1"}, {2, "changed text"}, {3, "text 3"}, {4, "text 4"}])

    :telemetry.detach(handler)

    assert Map.keys(found) |> Enum.sort() == [1, 3]
    assert_received :summary_query
    refute_received :summary_query
  end

  test "a summary written under an older prompt version is not served", %{version: v} do
    text = Summaries.section_text(@section)
    {:ok, s} = Summaries.put(v.id, 1, text, summary_attrs())
    Repo.update_all(SectionSummary, set: [prompt_version: "v1"])

    assert Summaries.prompt_version(:section) == "v2"
    assert Summaries.get(v.id, 1, text) == nil
    _ = s
  end
end
