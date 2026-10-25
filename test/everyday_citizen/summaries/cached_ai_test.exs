defmodule EverydayCitizen.Summaries.CachedAiTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.{AiSummary, Inputs}

  @src Records.SourceRef.new("https://x.test/cached", "c")

  setup do
    EverydayCitizen.FloorFixtures.iowa!()

    for {code, date} <- [{"is", ~D[2026-01-06]}, {"es", ~D[2026-01-20]}, {"enr", nil}] do
      {:ok, _} =
        Ingest.write(
          %Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: "119-s-5",
            code: code,
            classification: code,
            date: date,
            source: @src
          },
          nil
        )
    end

    # the undated version has no text; the newest with text is "es"
    Repo.update_all(
      from(v in Legislation.BillVersion, where: v.code in ["is", "es"]),
      set: [plain_text: "SEC. 1. The text."]
    )

    %{bill: Legislation.get_bill("federal", "119-s-5")}
  end

  test "bill_subjects names each bill's newest version with text, as Inputs.bill does", %{
    bill: bill
  } do
    {subject, _input} = Inputs.bill(bill)
    assert Inputs.bill_subjects([bill.id, -1]) == %{bill.id => subject}
    assert subject == "bill:#{bill.id}:es"
    assert Inputs.bill_subjects([]) == %{}
  end

  test "cached_ai finds summaries by subject under the current prompt version, without the text",
       %{bill: bill} do
    {subject, input} = Inputs.bill(bill)
    {:ok, _} = Summaries.put_ai(:bill, subject, input, %{summary: "Cached.", model: "m"})

    assert %{^subject => %AiSummary{summary: "Cached."}} =
             Summaries.cached_ai(:bill, [subject, "bill:0:none"])

    assert Summaries.cached_ai(:bill, []) == %{}

    Repo.update_all(AiSummary, set: [prompt_version: "old"])
    assert Summaries.cached_ai(:bill, [subject]) == %{}
  end
end
