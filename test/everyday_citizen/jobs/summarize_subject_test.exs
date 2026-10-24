defmodule EverydayCitizen.Jobs.SummarizeSubjectTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Jobs.SummarizeSubject
  alias EverydayCitizen.Legislation.BillVersion
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")

    for {code, date} <- [{"is", ~D[2026-01-06]}, {"es", ~D[2026-01-20]}] do
      {:ok, _} =
        EverydayCitizen.Ingest.write(
          %EverydayCitizen.Ingest.Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: "119-s-5",
            code: code,
            date: date,
            source: source_ref()
          },
          nil
        )
    end

    Repo.update_all(from(v in BillVersion, where: v.code == "is"), set: [plain_text: "Old text."])

    Repo.update_all(from(v in BillVersion, where: v.code == "es"),
      set: [plain_text: "SEC. 1. Newest text."]
    )

    %{bill: bill}
  end

  defp stub_claude do
    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "model" => "claude-haiku-5-5",
          "content" => [%{"type" => "text", "text" => "What the bill does."}],
          "usage" => %{"input_tokens" => 500, "output_tokens" => 40}
        })
      )
    end)
  end

  test "a bill's input is its newest version's full text", %{bill: bill} do
    assert {"bill:#{bill.id}:es", "SEC. 1. Newest text."} == Inputs.bill(bill)
  end

  test "a bill with no text has no input" do
    bill =
      EverydayCitizen.Legislation.get_bill("federal", "119-hr-1") ||
        %EverydayCitizen.Legislation.Bill{id: -1}

    assert Inputs.bill(bill) == nil
  end

  test "two requests at once queue one job; it writes, stores and tells the page", %{bill: bill} do
    {subject, input} = Inputs.bill(bill)
    assert :queued = Summaries.request_ai(:bill, subject, input)
    assert :queued = Summaries.request_ai(:bill, subject, input)
    assert [job] = all_enqueued(worker: SummarizeSubject)

    stub_claude()
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.ai_topic(:bill, subject))
    assert :ok = perform_job(SummarizeSubject, job.args)

    assert_received {:ai_summary, "bill", ^subject, {:ok, "What the bill does."}}
    assert {:cached, _} = Summaries.request_ai(:bill, subject, input)
  end

  test "new text for the version misses the cache", %{bill: bill} do
    {subject, input} = Inputs.bill(bill)
    {:ok, _} = Summaries.put_ai(:bill, subject, input, %{summary: "Old.", model: "m"})

    Repo.update_all(from(v in BillVersion, where: v.code == "es"),
      set: [plain_text: "SEC. 1. Changed."]
    )

    {^subject, changed} = Inputs.bill(bill)
    assert Summaries.get_ai(:bill, subject, changed) == nil
    assert :queued = Summaries.request_ai(:bill, subject, changed)
  end

  test "over budget, the job calls nothing and the page hears it is paused", %{bill: bill} do
    {subject, _} = Inputs.bill(bill)

    for _ <- 1..200,
        do: :ok = Summaries.record_usage(:section, %{input_tokens: 100_000, output_tokens: 0})

    Req.Test.stub(EverydayCitizen.Claude, fn _ -> flunk("no call over budget") end)
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.ai_topic(:bill, subject))

    assert {:cancel, :paused} =
             perform_job(SummarizeSubject, %{
               "kind" => "bill",
               "subject" => subject,
               "prompt_version" => "v1"
             })

    assert_received {:ai_summary, "bill", ^subject, {:error, :paused}}
  end
end
