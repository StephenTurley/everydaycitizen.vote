defmodule EverydayCitizenWeb.RepsLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true

  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest
  import EverydayCitizen.AccountsFixtures

  @census "test/support/fixtures/federal/census"
  @address "400 S Clinton St, Iowa City, IA 52240"

  setup do
    people = EverydayCitizen.FloorFixtures.iowa!()

    {:ok, _} =
      EverydayCitizen.Ingest.write(
        %EverydayCitizen.Ingest.Records.PostalDistricts{
          jurisdiction: "federal",
          rows: [
            %{postal_code: "52240", district_key: "IA-1", land_share: 1.0},
            %{postal_code: "52031", district_key: "IA-1", land_share: 0.947},
            %{postal_code: "52031", district_key: "IA-2", land_share: 0.053}
          ],
          source:
            EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/reps-live-postal", "z")
        },
        nil
      )

    {:ok, people}
  end

  # The home page asks for a ZIP code first; the full address form is one tap away.
  defp full_address(view) do
    view |> element("button", "Enter your full address instead") |> render_click()
    view
  end

  defp stub_census(file) do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      Plug.Conn.send_resp(conn, 200, File.read!("#{@census}/#{file}"))
    end)
  end

  test "an address leads to its district's reps page, and the address goes nowhere", %{conn: conn} do
    stub_census("iowa_city.json")
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:redirect, %{to: to}}} =
             view |> full_address() |> form("#address-form", address: @address) |> render_submit()

    assert to == "/district/IA-1"
    refute to =~ "Clinton"

    conn = get(recycle(conn), to)
    assert redirected_to(conn) == "/reps/IA-1"
    assert get_session(conn, :district) == "IA-1"

    {:ok, _view, html} = live(recycle(conn), "/reps/IA-1")
    refute html =~ "Clinton"
  end

  test "an address that cannot be found keeps what was typed", %{conn: conn} do
    stub_census("no_match.json")
    {:ok, view, _html} = live(conn, ~p"/")

    html =
      view |> full_address() |> form("#address-form", address: "99 Nowhere Rd") |> render_submit()

    assert html =~ "We couldn&#39;t find that address"
    assert html =~ ~s(value="99 Nowhere Rd")
  end

  test "a failing lookup service says so", %{conn: conn} do
    Req.Test.stub(EverydayCitizen.Federal, fn conn -> Plug.Conn.send_resp(conn, 500, "busy") end)
    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> full_address() |> form("#address-form", address: @address) |> render_submit()
    assert html =~ "Address lookup is unavailable"
  end

  test "the reps page shows the three reps, the first selected", %{conn: conn, grassley: g} do
    {:ok, view, html} = live(conn, ~p"/reps/IA-1")

    for name <- ["Chuck Grassley", "Joni Ernst", "Mariannette Miller-Meeks"],
        do: assert(html =~ name)

    assert has_element?(view, ~s(a[aria-current="page"][href="/reps/IA-1?rep=#{g.id}"]))
    assert has_element?(view, ~s(a[href="/this-week"]), "This week's schedule")
    assert html =~ "Sen." or html =~ "Senate"
  end

  test "picking a rep opens their latest week; another week and a filter patch the page", %{
    conn: conn,
    ernst: e
  } do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1")

    view
    |> element(~s(nav[aria-label="Representatives"] a[href="/reps/IA-1?rep=#{e.id}"]))
    |> render_click()

    assert_patch(view, "/reps/IA-1?rep=#{e.id}")
    # her latest activity is the Jan 20 vote
    assert has_element?(view, "#week", "Jan 19 – Jan 25")
    assert render(view) =~ "Voted Nay"
    refute render(view) =~ "Introduced a bill"

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-05")
    assert render(view) =~ "Introduced a bill"
    refute render(view) =~ "Voted Nay"

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19&filter=votes")
    assert render(view) =~ "Voted Nay"
  end

  test "the week switcher keeps the rep and filter, and stops at the current week", %{
    conn: conn,
    ernst: e
  } do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19&filter=votes")

    assert has_element?(
             view,
             ~s(#week a[aria-label="Previous week"][href="/reps/IA-1?filter=votes&rep=#{e.id}&week=2026-01-12"])
           )

    assert has_element?(view, ~s(#week a[aria-label="Next week"][href*="week=2026-01-26"]))

    monday =
      DateTime.now!("America/New_York")
      |> DateTime.to_date()
      |> Date.beginning_of_week()
      |> Date.to_iso8601()

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=#{monday}")
    refute has_element?(view, ~s(#week a[aria-label="Next week"]))
  end

  test "a malformed or future week opens the latest week instead", %{conn: conn, ernst: e} do
    for week <- ["nope", "2099-01-05"] do
      {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=#{week}")
      assert has_element?(view, "#week", "Jan 19 – Jan 25")
    end
  end

  test "a week with nothing on the record says so and asks for no summary", %{
    conn: conn,
    ernst: e
  } do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-03-02")
    assert render(view) =~ "Nothing on the record for this week."
    refute has_element?(view, "#week-summary")
    assert [] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)
  end

  test "a week with activity shows its summary at the top", %{conn: conn, ernst: e} do
    {subject, input} = EverydayCitizen.Summaries.Inputs.rep_week(e.id, ~D[2026-01-19])
    assert input =~ "Voted nay"
    assert input =~ "S. 5"

    {:ok, _} =
      EverydayCitizen.Summaries.put_ai(:rep_week, subject, input, %{
        summary: "She voted against one bill.",
        model: "m"
      })

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19")
    assert has_element?(view, "#week-summary", "She voted against one bill.")
    assert has_element?(view, "#week-summary", "Written by AI from this week's record below")
  end

  test "a new vote in a week already summarized gets a fresh summary", %{conn: conn, ernst: e} do
    {subject, input} = EverydayCitizen.Summaries.Inputs.rep_week(e.id, ~D[2026-01-19])

    {:ok, _} =
      EverydayCitizen.Summaries.put_ai(:rep_week, subject, input <> " (old)", %{
        summary: "Stale.",
        model: "m"
      })

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19")
    assert has_element?(view, "#week-summary", "Writing a plain-English summary")
    assert [_] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)
  end

  test "a crawler is shown a week's summary already written but never starts one", %{
    conn: conn,
    ernst: e
  } do
    conn = Plug.Conn.put_req_header(conn, "user-agent", "facebookexternalhit/1.1")

    {:ok, view, html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19")
    refute has_element?(view, "#week-summary")
    refute html =~ "Writing a plain-English summary"
    assert [] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)

    {subject, input} = EverydayCitizen.Summaries.Inputs.rep_week(e.id, ~D[2026-01-19])

    {:ok, _} =
      EverydayCitizen.Summaries.put_ai(:rep_week, subject, input, %{
        summary: "Cached.",
        model: "m"
      })

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19")
    assert has_element?(view, "#week-summary", "Cached.")
  end

  test "a vote with no bill shows what was voted on, and defines the procedure", %{
    conn: conn,
    ernst: e
  } do
    {:ok, _} =
      EverydayCitizen.Ingest.write(
        %EverydayCitizen.Ingest.Records.Vote{
          jurisdiction: "federal",
          body_external_id: "senate",
          session_identifier: "119-2",
          external_id: "senate-119-2-9",
          identifier: "Roll Call 9",
          question: "On the Cloture Motion",
          classification: "cloture",
          result: "Cloture Motion Agreed to",
          passed: true,
          voted_at: ~U[2026-01-21 17:00:00Z],
          description: "Todd Blanche, of Florida, to be Attorney General",
          subject_ref: "PN1078",
          counts: %{yea: 52, nay: 47, present: 0, absent: 1},
          positions: [
            %{
              person: {"bioguide", "E000295"},
              raw_label: "Ernst",
              option: "yea",
              raw_option: "Yea"
            }
          ],
          source: EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/v", "v")
        },
        nil
      )

    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{e.id}&week=2026-01-19")
    assert render(view) =~ "Todd Blanche, of Florida, to be Attorney General"
    assert render(view) =~ "On the Cloture Motion"
    assert has_element?(view, "details summary", "What is cloture?")
    assert has_element?(view, "details", "end debate")
  end

  test "items link to their bill pages", %{conn: conn, grassley: g} do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{g.id}")
    assert has_element?(view, ~s(a[href="/bills/119-s-5"]))
  end

  test "a rep with nothing in the filter sees Nothing yet", %{conn: conn, miller_meeks: m} do
    {:ok, _view, html} = live(conn, ~p"/reps/IA-1?rep=#{m.id}")
    assert html =~ "Nothing on the record for this week."
  end

  test "home says what you will find and links to this week", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    for heading <- ["How they voted", "What they introduced", "The text itself"],
        do: assert(html =~ heading)

    assert has_element?(view, ~s(a[href="/this-week"]), "See what's scheduled this week")
  end

  test "pages carry the site's name in the header and the title", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert has_element?(view, ~s(header a[href="/"]), "Everyday Citizen")
    assert html =~ "Find your representatives · Everyday Citizen"
    refute html =~ "The Floor"
  end

  test "home offers your saved district", %{conn: conn} do
    conn = conn |> init_test_session(%{district: "IA-1"})
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ ~s(href="/reps/IA-1")
  end

  test "a vote's line does not repeat a question its result already states", %{
    conn: conn,
    grassley: g
  } do
    EverydayCitizen.Repo.update_all(EverydayCitizen.Votes.Vote,
      set: [
        question: "On Cloture on the Motion to Proceed",
        result: "Cloture on the Motion to Proceed Rejected"
      ]
    )

    {:ok, _view, html} = live(conn, ~p"/reps/IA-1?rep=#{g.id}&filter=votes")
    assert html =~ "Cloture on the Motion to Proceed Rejected, 64–35."
    refute html =~ "On Cloture on the Motion to Proceed. Cloture"
  end

  test "the form also works without the live connection, by POST, never GET", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ ~s(method="post")
    assert html =~ ~s(action="/district")
    assert render(full_address(view)) =~ ~s(id="address-form")

    stub_census("iowa_city.json")
    conn = post(conn, ~p"/district", %{"address" => @address})
    assert redirected_to(conn) == "/reps/IA-1"
    assert get_session(conn, :district) == "IA-1"
  end

  test "a POST lookup that fails goes back home with a message and no address", %{conn: conn} do
    stub_census("no_match.json")
    conn = post(conn, ~p"/district", %{"address" => "99 Nowhere Rd"})
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "couldn't find that address"
    refute redirected_to(conn) =~ "Nowhere"
  end

  test "a blank address is caught before any lookup", %{conn: conn} do
    Req.Test.stub(EverydayCitizen.Federal, fn _conn -> flunk("no lookup expected") end)
    {:ok, view, _html} = live(conn, ~p"/")

    assert view |> full_address() |> form("#address-form", address: "  ") |> render_submit() =~
             "Enter your address"
  end

  test "a district key that names no place is not saved", %{conn: conn} do
    conn = get(conn, "/district/nonsense")
    assert redirected_to(conn) == "/"
    refute get_session(conn, :district)
  end

  test "a ZIP code in one district goes straight to its reps", %{conn: conn} do
    Req.Test.stub(EverydayCitizen.Federal, fn _conn -> flunk("no address lookup expected") end)
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:redirect, %{to: "/district/IA-1"}}} =
             view |> form("#zip-form", zip: "52240") |> render_submit()
  end

  test "a ZIP code split between districts asks for the street", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> form("#zip-form", zip: "52031") |> render_submit()

    assert html =~ "52031 is split between IA-1 and IA-2"
    assert html =~ ~s(id="street-form")

    stub_census("iowa_city.json")

    assert {:error, {:redirect, %{to: "/district/IA-1"}}} =
             view |> form("#street-form", street: "400 S Clinton St") |> render_submit()
  end

  test "an unknown ZIP code falls back to the full address", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> form("#zip-form", zip: "20500") |> render_submit()
    assert html =~ "We don&#39;t have that ZIP code"
    assert html =~ ~s(id="address-form")
  end

  test "a ZIP code must be five digits", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert view |> form("#zip-form", zip: "123") |> render_submit() =~ "Enter a 5-digit ZIP code"
  end

  test "ZIP codes work by POST without the live connection", %{conn: conn} do
    conn1 = post(conn, ~p"/district", %{"zip" => "52240"})
    assert redirected_to(conn1) == "/reps/IA-1"

    conn2 = post(conn, ~p"/district", %{"zip" => "52031"})
    assert redirected_to(conn2) == "/"
    assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "more than one district"

    stub_census("iowa_city.json")
    conn3 = post(conn, ~p"/district", %{"zip" => "52031", "street" => "400 S Clinton St"})
    assert redirected_to(conn3) == "/reps/IA-1"
  end

  test "a signed-in person can follow a rep", %{conn: conn, grassley: g} do
    conn = log_in_user(conn, user_fixture())
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{g.id}")

    view |> element("#follow-rep") |> render_click()
    assert has_element?(view, ~s(#follow-rep[aria-pressed="true"]), "Following")
  end

  test "signed out, following a rep leads to sign-in and back", %{conn: conn, grassley: g} do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{g.id}")
    to = URI.encode_www_form("/reps/IA-1?rep=#{g.id}")
    assert has_element?(view, ~s(a[href="/users/sign-in-to?to=#{to}"]), "Follow")
  end
end
