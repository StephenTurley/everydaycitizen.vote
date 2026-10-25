defmodule EverydayCitizenWeb.HomeLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true

  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  @src Records.SourceRef.new("https://x.test/home", "h")
  @googlebot "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    :ok
  end

  # `n` bills that became law on successive days of October, the last newest;
  # each has a text version, so each can have a plain-English summary.
  defp laws!(n) do
    for i <- 1..n do
      id = "119-hr-#{i}"

      {:ok, _} =
        Ingest.write(
          %Records.Bill{
            jurisdiction: "federal",
            session_identifier: "119",
            external_id: id,
            identifier: "H.R. #{i}",
            classification: "bill",
            title: "Law number #{i}",
            source: @src
          },
          nil
        )

      {:ok, _} =
        Ingest.write(
          %Records.BillActions{
            jurisdiction: "federal",
            bill_external_id: id,
            actions: [
              %Records.BillAction{
                position: 0,
                date: Date.new!(2026, 10, i),
                description: "Became Public Law",
                classification: "became_law"
              }
            ],
            source: @src
          },
          nil
        )

      {:ok, _} =
        Ingest.write(
          %Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: id,
            code: "enr",
            classification: "enr",
            date: Date.new!(2026, 10, i),
            source: @src
          },
          nil
        )
    end

    EverydayCitizen.Repo.update_all(EverydayCitizen.Legislation.BillVersion,
      set: [plain_text: "SEC. 1. The text."]
    )

    :ok
  end

  defp bill(i), do: Legislation.get_bill("federal", "119-hr-#{i}")

  defp event!(id, at, bills) do
    {:ok, _} =
      Ingest.write(
        %Records.Event{
          jurisdiction: "federal",
          body_external_id: "senate",
          external_id: id,
          classification: "floor",
          title: "Floor session #{id}",
          start_at: at,
          bill_external_ids: bills,
          raw_bill_labels: [],
          source: @src
        },
        nil
      )
  end

  defp days_from_now(n), do: DateTime.add(DateTime.utc_now(), n * 86_400, :second)

  describe "new laws" do
    setup do
      laws!(7)
    end

    test "the five newest laws link to their bill pages, newest first", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")
      assert html =~ "New laws"
      assert html =~ "Signed most recently"
      assert has_element?(view, ~s(a[href="/bills/119-hr-7"]), "Law number 7")
      assert has_element?(view, ~s(a[href="/bills/119-hr-3"]), "Law number 3")
      refute has_element?(view, ~s(a[href="/bills/119-hr-2"]))
      assert has_element?(view, "#law-119-hr-7", "Became law")
      assert has_element?(view, "#law-119-hr-7", "Oct 7")
      assert has_element?(view, "#law-119-hr-7", "H.R. 7")
      assert html =~ ~r/Law number 7.*Law number 6/s
    end

    test "Show 5 more loads the rest in place, then the button goes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("button", "Show 5 more") |> render_click()
      assert has_element?(view, ~s(a[href="/bills/119-hr-1"]), "Law number 1")
      assert has_element?(view, ~s(a[href="/bills/119-hr-7"]))
      refute has_element?(view, "button", "Show 5 more")
    end

    test "a cached plain-English summary shows with its AI label", %{conn: conn} do
      {subject, input} = Inputs.bill(bill(7))

      {:ok, _} =
        Summaries.put_ai(:bill, subject, input, %{summary: "It names a post office.", model: "m"})

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#law-119-hr-7", "It names a post office.")
      assert has_element?(view, "#law-119-hr-7", "Written by AI from the bill; it can be wrong")
    end

    test "summaries not written yet are asked for, and each lands on its own card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#law-119-hr-7", "Writing a plain-English summary")
      assert length(all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)) == 5

      {subject, _} = Inputs.bill(bill(6))
      send(view.pid, {:ai_summary, "bill", subject, {:ok, "Six is summarized."}})
      assert has_element?(view, "#law-119-hr-6", "Six is summarized.")
      refute has_element?(view, "#law-119-hr-7", "Six is summarized.")
      assert has_element?(view, "#law-119-hr-7", "Writing a plain-English summary")

      {subject, _} = Inputs.bill(bill(5))
      send(view.pid, {:ai_summary, "bill", subject, {:error, :paused}})
      refute has_element?(view, "#law-119-hr-5", "Writing a plain-English summary")
    end

    test "a crawler never starts a summary, but sees one already written", %{conn: conn} do
      conn = Plug.Conn.put_req_header(conn, "user-agent", @googlebot)
      {:ok, view, html} = live(conn, ~p"/")
      refute html =~ "Writing a plain-English summary"
      view |> element("button", "Show 5 more") |> render_click()
      assert [] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)

      {subject, input} = Inputs.bill(bill(7))
      {:ok, _} = Summaries.put_ai(:bill, subject, input, %{summary: "Cached.", model: "m"})
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#law-119-hr-7", "Cached.")
    end
  end

  test "with no laws yet, there is no Show more", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    refute has_element?(view, "button", "Show 5 more")
  end

  test "without a district: the ZIP finder, and no Your reps card", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, "#zip-form")
    assert html =~ "See what your own representatives did: your ZIP code"
    refute has_element?(view, "#your-reps")
  end

  test "with a district: the Your reps card, and no finder", %{conn: conn} do
    conn = init_test_session(conn, %{district: "IA-1"})
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#your-reps", "Your reps")
    assert has_element?(view, "#your-reps", "Iowa's 1st district")
    assert has_element?(view, ~s(#your-reps a[href="/reps/IA-1"]), "See their week")
    refute has_element?(view, "#zip-form")
  end

  test "no votes scheduled: says so, with the next session on the calendar", %{conn: conn} do
    at = days_from_now(2)
    event!("bare", at, [])
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#coming-up", "No votes are scheduled yet.")

    day = at |> DateTime.shift_zone!("America/New_York") |> Calendar.strftime("%b %-d")
    assert has_element?(view, "#coming-up", "Next on the calendar: #{day}, Floor session bare")
    assert has_element?(view, ~s(a[href="/this-week"]), "This week's schedule")
  end

  test "a scheduled vote shows its chamber, title and bill links", %{conn: conn} do
    event!("vote", days_from_now(1), ["119-s-5"])
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#coming-up", "Senate")
    assert has_element?(view, "#coming-up", "Floor session vote")
    assert has_element?(view, ~s(#coming-up a[href="/bills/119-s-5"]), "S. 5")
    refute has_element?(view, "#coming-up", "No votes are scheduled yet.")
  end

  test "the page is titled for its news", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "New laws and your representatives · Everyday Citizen"
    refute html =~ "What are your representatives doing?"
  end
end
