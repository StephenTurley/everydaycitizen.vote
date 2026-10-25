defmodule EverydayCitizen.Summaries.ChangeSummaryTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import EverydayCitizen.HistoryFixtures

  alias EverydayCitizen.Jobs.SummarizeSubject
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    %{bill: three_versions!()}
  end

  test "a changed section's input holds its wording before and after the change", %{bill: bill} do
    {subject, input} = Inputs.change(bill, "eh", 1)

    assert subject == "change:#{bill.id}:eh:1"
    assert input =~ ~r{<before>\n.*The term covered investment—.*</before>}s
    assert input =~ ~r{<after>\n.*similar means\..*</after>}s
  end

  test "an added section's input is its text alone", %{bill: bill} do
    {_subject, input} = Inputs.change(bill, "eh", 2)
    assert input =~ ~r{^<added>\n.*photo identification.*</added>$}s
    refute input =~ "<before>"
  end

  test "an unchanged section has no input", %{bill: bill} do
    assert Inputs.change(bill, "eh", 0) == nil
  end

  test "the subject rebuilds the same input", %{bill: bill} do
    {subject, input} = Inputs.change(bill, "eh", 1)
    assert Inputs.input("change", subject) == input
    assert Inputs.input("change", "change:nonsense") == nil
  end

  test "the job writes the explanation and tells the page", %{bill: bill} do
    {subject, input} = Inputs.change(bill, "eh", 1)

    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body)["system"] =~ "change"

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "model" => "claude-haiku-5-5",
          "stop_reason" => "end_turn",
          "content" => [%{"type" => "text", "text" => "The definition became one sentence."}],
          "usage" => %{"input_tokens" => 300, "output_tokens" => 20}
        })
      )
    end)

    assert :queued = Summaries.request_ai(:change, subject, input)
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.ai_topic(:change, subject))
    [job] = all_enqueued(worker: SummarizeSubject)
    assert :ok = perform_job(SummarizeSubject, job.args)

    assert_received {:ai_summary, "change", ^subject,
                     {:ok, "The definition became one sentence."}}
  end
end
