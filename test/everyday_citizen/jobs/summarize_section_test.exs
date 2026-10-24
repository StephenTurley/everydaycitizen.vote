defmodule EverydayCitizen.Jobs.SummarizeSectionTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Jobs.SummarizeSection
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.SectionSummary

  @sections [
    %{"kind" => "title", "enum" => "I", "heading" => "Main"},
    %{
      "kind" => "section",
      "enum" => "1.",
      "heading" => "Short title",
      "blocks" => [
        %{
          "level" => 0,
          "enum" => nil,
          "heading" => nil,
          "text" => "This Act may be cited as the Sample Act."
        }
      ]
    }
  ]

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

    version = EverydayCitizen.Legislation.get_version(bill, "is")
    :ok = EverydayCitizen.Legislation.put_sections(version.id, @sections, 2)
    %{version: version, text: Summaries.section_text(Enum.at(@sections, 1))}
  end

  # today's spend reaches the $2.00 budget (20M input tokens at $0.10/M)
  defp spend_budget! do
    for _ <- 1..200,
        do: :ok = Summaries.record_usage(:section, %{input_tokens: 100_000, output_tokens: 0})
  end

  defp stub_claude(status \\ 200) do
    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      body =
        if status == 200,
          do: %{
            "model" => "claude-haiku-5-5",
            "content" => [%{"type" => "text", "text" => "This section gives the bill its name."}],
            "usage" => %{"input_tokens" => 90, "output_tokens" => 10}
          },
          else: %{"type" => "error"}

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(body))
    end)
  end

  test "a miss queues one job; asking again while it waits queues nothing", %{
    version: v,
    text: text
  } do
    assert :queued = Summaries.request(v.id, 1, text)
    assert :queued = Summaries.request(v.id, 1, text)
    assert [_one] = all_enqueued(worker: SummarizeSection)
  end

  test "the job writes the summary once and tells the open pages", %{version: v, text: text} do
    stub_claude()
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.topic(v.id, 1))

    assert :ok =
             perform_job(SummarizeSection, %{
               "version_id" => v.id,
               "index" => 1,
               "prompt_version" => "v1"
             })

    assert_received {:section_summary, 1, {:ok, "This section gives the bill its name."}}
    assert %SectionSummary{input_tokens: 90} = Summaries.get(v.id, 1, text)
    assert {:cached, _} = Summaries.request(v.id, 1, text)
    assert [] = all_enqueued(worker: SummarizeSection)
  end

  test "once the day's budget is spent, new summaries pause and nothing is queued", %{
    version: v,
    text: text
  } do
    spend_budget!()

    assert :paused = Summaries.request(v.id, 1, text)
    assert [] = all_enqueued(worker: SummarizeSection)
  end

  test "a very long section is not sent", %{version: v} do
    assert :too_long = Summaries.request(v.id, 1, String.duplicate("a", 40_001))
    assert [] = all_enqueued(worker: SummarizeSection)
  end

  test "when the last attempt fails, open pages hear it isn't available", %{version: v} do
    stub_claude(500)
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.topic(v.id, 1))

    assert {:error, _} =
             perform_job(
               SummarizeSection,
               %{"version_id" => v.id, "index" => 1, "prompt_version" => "v1"},
               attempt: 3
             )

    assert_received {:section_summary, 1, {:error, :unavailable}}
  end

  test "an earlier failed attempt stays quiet so the retry can still succeed", %{version: v} do
    stub_claude(500)
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.topic(v.id, 1))

    assert {:error, _} =
             perform_job(
               SummarizeSection,
               %{"version_id" => v.id, "index" => 1, "prompt_version" => "v1"},
               attempt: 1
             )

    refute_received {:section_summary, _, _}
  end

  test "a queued job re-checks the day's budget and calls nothing once it is spent", %{
    version: v
  } do
    spend_budget!()

    Req.Test.stub(EverydayCitizen.Claude, fn _conn -> flunk("no call over budget") end)
    Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.topic(v.id, 1))

    assert {:cancel, :paused} =
             perform_job(SummarizeSection, %{
               "version_id" => v.id,
               "index" => 1,
               "prompt_version" => "v1"
             })

    assert_received {:section_summary, 1, {:error, :paused}}
  end
end
