defmodule EverydayCitizenWeb.BillHistoryLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest
  import EverydayCitizen.HistoryFixtures

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  @src Records.SourceRef.new("https://x.test/v", "v")

  defp w(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  setup %{conn: conn} do
    people = EverydayCitizen.FloorFixtures.iowa!()
    bill = three_versions!()

    w(%Records.Body{
      jurisdiction: "federal",
      external_id: "ssju00",
      name: "Senate Committee on the Judiciary",
      classification: "committee",
      source: @src
    })

    w(%Records.Membership{
      jurisdiction: "federal",
      person: {"bioguide", "G000386"},
      body_external_id: "ssju00",
      role: "member",
      source: @src
    })

    w(%Records.BillCommittees{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      activities: [%{body_external_id: "ssju00", kind: "markup", date: ~D[2026-01-14]}],
      source: @src
    })

    w(%Records.BillRelations{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      relations: [%{bill_external_id: "119-sres-10", kind: "procedural"}],
      source: @src
    })

    w(%Records.BillAmendments{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      amendments: [
        %{
          external_id: "119-samdt-9",
          identifier: "S.Amdt. 9",
          description: "Under the resolution, a substitute is considered adopted.",
          latest_action: "Agreed to without objection.",
          latest_action_date: ~D[2026-07-22],
          url: "https://example.test/samdt/9",
          agreed: true
        }
      ],
      source: @src
    })

    w(%Records.Vote{
      jurisdiction: "federal",
      body_external_id: "senate",
      session_identifier: "119-2",
      external_id: "senate-119-2-60",
      identifier: "Roll Call 60",
      question: "On Agreeing to the Resolution",
      result: "Passed",
      voted_on: ~D[2026-07-21],
      voted_at: ~U[2026-07-21 17:00:00Z],
      bill_external_id: "119-sres-10",
      counts: %{yea: 51, nay: 49, present: 0, absent: 0},
      positions: [
        %{person: {"bioguide", "E000295"}, raw_label: "Ernst", option: "yea", raw_option: "Yea"}
      ],
      source: @src
    })

    Map.merge(people, %{bill: bill, conn: init_test_session(conn, %{district: "IA-1"})})
  end

  test "a part added in a later version says which version added it", %{conn: conn, bill: bill} do
    EverydayCitizen.Repo.update_all(EverydayCitizen.Legislation.BillVersion,
      set: [plain_text: "SEC. 1. The text."]
    )

    {subject, input} = EverydayCitizen.Summaries.Inputs.bill(bill)
    assert subject =~ ~r/:eh$/

    story =
      "It limits trading.\n\n## If this becomes law\n- Lawmakers: they could not buy stocks.\n- If you vote: you would need photo ID.\n\n## Subjects\n- Trading rules: SEC. 2\n- Photo ID to vote: SEC. 3"

    {:ok, _} =
      EverydayCitizen.Summaries.put_ai(:bill, subject, input, %{summary: story, model: "m"})

    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh")

    assert has_element?(
             view,
             "#bill-summary",
             "The Photo ID to vote part was added in the version of Jul 22, 2026"
           )

    assert has_element?(view, ~s(#bill-summary a[href="/bills/119-s-5?version=eh"]))
    refute has_element?(view, "#bill-summary", "Trading rules part was added")
  end

  test "each section says where it came from", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh")
    assert has_element?(view, "#section-0", "Since introduced")
    assert has_element?(view, "#section-1", "Changed")
    assert has_element?(view, "#section-2", "Added Jul 22")
  end

  test "an added section shows the step that added it, the rule's vote and your reps' part", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=2")

    assert has_element?(view, "#origin-2", "Where this section came from")
    assert has_element?(view, "#origin-2", "Not in the first version")

    assert has_element?(
             view,
             "#origin-2",
             "Under the resolution, a substitute is considered adopted."
           )

    assert has_element?(view, ~s(#origin-2 a[href="https://example.test/samdt/9"]))
    assert has_element?(view, "#origin-2 details summary", "considered adopted")
    assert [_ | _] = assert_details_keep_open(render(view))
    assert has_element?(view, "#origin-2", "Roll Call 60")
    assert has_element?(view, "#origin-2 [data-rep]", "Joni Ernst")
    assert has_element?(view, "#origin-2 [data-rep]", "Yea")
  end

  test "reps named in the text history link to their pages", %{conn: conn, ernst: ernst} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=2")

    assert has_element?(
             view,
             ~s(#origin-2 [data-rep] a[href="/people/#{ernst.id}"]),
             "Joni Ernst"
           )
  end

  test "a changed section shows the committee step, its member rep, and the change marked in the text",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=1")

    assert has_element?(view, "#origin-1", "Marked up by Senate Committee on the Judiciary")
    assert has_element?(view, "#origin-1 [data-rep]", "Sits on Senate Committee on the Judiciary")
    assert has_element?(view, "#origin-1", "Committee members' individual votes")
    assert has_element?(view, "#comparison-1 del", "; and")
    assert has_element?(view, "#comparison-1 ins", ".")
  end

  test "a change's cached AI explanation shows beside it", %{conn: conn, bill: bill} do
    {subject, input} = EverydayCitizen.Summaries.Inputs.change(bill, "eh", 1)

    {:ok, _} =
      EverydayCitizen.Summaries.put_ai(:change, subject, input, %{
        summary: "One sentence now.",
        model: "m"
      })

    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=1")
    assert has_element?(view, "#change-summary-1", "One sentence now.")
    assert has_element?(view, "#change-summary-1", "Written by AI from the two versions")
  end

  test "opening a change asks for its explanation; a crawler never does", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=2")

    assert [%{args: %{"kind" => "change"}}] =
             all_enqueued(
               worker: EverydayCitizen.Jobs.SummarizeSubject,
               args: %{"kind" => "change"}
             )

    EverydayCitizen.Repo.delete_all(Oban.Job)
    bot = Plug.Conn.put_req_header(conn, "user-agent", "Googlebot/2.1")
    {:ok, _view, _html} = live(bot, ~p"/bills/119-s-5?version=eh&section=2")

    assert [] =
             all_enqueued(
               worker: EverydayCitizen.Jobs.SummarizeSubject,
               args: %{"kind" => "change"}
             )
  end

  test "a rep whose chamber hasn't voted on the change is told so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=2")

    assert has_element?(
             view,
             "#origin-2 [data-rep]",
             "The House of Representatives hasn't voted on this change."
           )

    assert has_element?(view, "#origin-2 [data-rep]", "Chuck Grassley")
    assert has_element?(view, "#origin-2 [data-rep]", "No recorded vote on this change.")
  end

  test "an unchanged section has no panel", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=eh&section=0")
    refute has_element?(view, "#origin-0")
  end
end
