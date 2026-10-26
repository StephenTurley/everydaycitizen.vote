defmodule EverydayCitizenWeb.SearchLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true

  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  @src Records.SourceRef.new("https://x.test/search-live", "s")

  setup do
    {:ok, EverydayCitizen.FloorFixtures.iowa!()}
  end

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp bill!(external_id, identifier, title, text \\ nil) do
    bill =
      write!(%Records.Bill{
        jurisdiction: "federal",
        session_identifier: "119",
        external_id: external_id,
        identifier: identifier,
        classification: "bill",
        title: title,
        from_body_external_id: "senate",
        introduced_on: ~D[2025-02-01],
        source: @src
      })

    if text do
      write!(%Records.BillVersion{
        jurisdiction: "federal",
        bill_external_id: external_id,
        code: "is",
        classification: "is",
        date: ~D[2025-02-01],
        source: @src
      })

      write!(%Records.BillVersionText{
        jurisdiction: "federal",
        bill_external_id: external_id,
        code: "is",
        xml: "<bill/>",
        xml_schema: "other",
        plain_text: text,
        source: @src
      })
    end

    bill
  end

  test "results show name matches, text matches and people, and the page is noindex", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/search?q=laken riley")
    assert html =~ ~s(name="robots" content="noindex")
    assert html =~ ">Search · Everyday Citizen</title>"

    assert has_element?(
             view,
             "section[aria-label='Bills with this name'] a[href='/bills/119-s-5']"
           )

    assert has_element?(view, "section[aria-label='Bills with this name']", "S. 5")
    assert has_element?(view, "section[aria-label='Bills with this name']", "Passed a chamber")
  end

  test "other pages are not noindex", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/this-week")
    refute html =~ "noindex"
  end

  test "a cached summary shows under its AI label", %{conn: conn} do
    bill = bill!("119-s-77", "S. 77", "Sunshine Clock Act", "Sec. 1. Clocks stay put.")
    {subject, input} = Inputs.bill(bill)
    {:ok, _} = Summaries.put_ai(:bill, subject, input, %{summary: "Keeps clocks.", model: "m"})

    {:ok, view, _html} = live(conn, ~p"/search?q=sunshine clock")
    assert has_element?(view, "section[aria-label='Bills with this name']", "Keeps clocks.")

    assert has_element?(
             view,
             "section[aria-label='Bills with this name']",
             "Written by AI from the bill; it can be wrong"
           )
  end

  test "a result with a story shows its first group", %{conn: conn} do
    bill = bill!("119-s-78", "S. 78", "Sunshine Lamp Act", "Sec. 1. Lamps stay lit.")
    {subject, input} = Inputs.bill(bill)

    story =
      "Keeps lamps lit.\n\n## If this becomes law\n- If you own a lamp: it would stay lit.\n- Lamp makers: they would label lamps.\n\n## Tags\nSets rules"

    {:ok, _} = Summaries.put_ai(:bill, subject, input, %{summary: story, model: "m"})

    {:ok, view, _html} = live(conn, ~p"/search?q=sunshine lamp")
    section = "section[aria-label='Bills with this name']"
    assert has_element?(view, section, "If you own a lamp")
    assert has_element?(view, section, "it would stay lit.")
    assert has_element?(view, section, "Sets rules")
    refute has_element?(view, section, "Keeps lamps lit.")
    refute has_element?(view, section, "Lamp makers")
  end

  test "text matches show the section and mark the words, escaping the rest", %{conn: conn} do
    bill!(
      "119-s-80",
      "S. 80",
      "An unrelated title",
      "SECTION 1. Rules.\n<b>bold</b> the walrus shall be protected."
    )

    {:ok, view, html} = live(conn, ~p"/search?q=walrus")
    section = "section[aria-label='Bills whose text mentions it']"
    assert has_element?(view, "#{section} a[href='/bills/119-s-80']")
    assert has_element?(view, "#{section} mark", "walrus")
    refute html =~ "<b>bold</b>"
  end

  test "text results page ten at a time, and a bad page number falls back", %{conn: conn} do
    for n <- 1..12, do: bill!("119-s-#{200 + n}", "S. #{200 + n}", "Title #{n}", "Walrus rules.")

    {:ok, view, _html} = live(conn, ~p"/search?q=walrus")
    section = "section[aria-label='Bills whose text mentions it']"
    assert has_element?(view, section, "2 more bills mention it")
    assert has_element?(view, "#{section} a[href='/search?q=walrus&page=2']")

    {:ok, view, _html} = live(conn, ~p"/search?q=walrus&page=2")
    assert has_element?(view, "#{section} a[href^='/bills/']")

    for bad <- ["0", "-3", "abc"] do
      {:ok, view, _html} = live(conn, ~p"/search?q=walrus&page=#{bad}")
      assert has_element?(view, section, "2 more bills mention it")
    end
  end

  test "a bare number lists the bills with it", %{conn: conn} do
    bill!("119-hr-55", "H.R. 55", "Another bill")
    bill!("119-s-55", "S. 55", "A third bill")
    {:ok, view, _html} = live(conn, ~p"/search?q=55")
    assert has_element?(view, "section[aria-label='Bills numbered 55'] a[href='/bills/119-s-55']")

    assert has_element?(
             view,
             "section[aria-label='Bills numbered 55'] a[href='/bills/119-hr-55']"
           )
  end

  test "a hand-typed address in the URL is not searched and leaves the address bar", %{
    conn: conn
  } do
    assert {:error, {_kind, %{to: "/search"}}} = result = live(conn, ~p"/search?q=123 Main St")
    {:ok, view, html} = follow_redirect(result, conn)
    assert html =~ "looks like an address"
    assert has_element?(view, ~s(a[href="/"]), "looks like an address")
    refute html =~ "Main St"
    refute html =~ "Bills with this name"
    refute html =~ "Search for a bill"
  end

  test "a state and ZIP code with no such bill is handled as an address", %{conn: conn} do
    for q <- ["IA 50309", "ia50309"] do
      assert {:error, {_kind, %{to: "/search"}}} = result = live(conn, ~p"/search?q=#{q}")
      {:ok, _view, html} = follow_redirect(result, conn)
      assert html =~ "looks like an address"
      refute html =~ "50309"
    end

    {:ok, view, _html} = live(conn, ~p"/search?q=laken riley")
    render_patch(view, ~p"/search?q=IA 50309")
    assert_patched(view, "/search")
    assert render(view) =~ "looks like an address"
  end

  test "a five-digit bill number that is stored is searched", %{conn: conn} do
    bill!("119-hr-10545", "H.R. 10545", "A Long-Numbered Act")
    {:ok, view, _html} = live(conn, ~p"/search?q=hr10545")
    assert has_element?(view, ~s(a[href="/bills/119-hr-10545"]))
  end

  test "an address patched in on a live page also leaves the address bar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search?q=laken riley")
    render_patch(view, ~p"/search?q=123 Main St")
    assert_patched(view, "/search")
    html = render(view)
    assert html =~ "looks like an address"
    refute html =~ "Main St"
  end

  test "a place named in the query comes before the bill groups", %{conn: conn} do
    bill!("119-s-90", "S. 90", "Unrelated title", "Grants for Iowa farms.")
    {:ok, _view, html} = live(conn, ~p"/search?q=iowa")
    {place, _} = :binary.match(html, ~s(aria-label="Iowa"))
    {text, _} = :binary.match(html, ~s(aria-label="Bills whose text mentions it"))
    assert place < text
  end

  test "a state search lists its members with links to their pages", %{
    conn: conn,
    grassley: grassley
  } do
    {:ok, view, html} = live(conn, ~p"/search?q=iowa")
    assert has_element?(view, ~s(a[href="/people/#{grassley.id}"]))
    assert has_element?(view, "section[aria-label='Iowa']", "Senate · Republican · Iowa")
    refute html =~ ~r/senate/
  end

  test "a name search lists people", %{conn: conn, ernst: ernst} do
    {:ok, view, _html} = live(conn, ~p"/search?q=joni ernst")
    assert has_element?(view, ~s(section[aria-label="People"] a[href="/people/#{ernst.id}"]))
  end

  test "no AI summary is started by searching", %{conn: conn} do
    live(conn, ~p"/search?q=laken riley")
    refute_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)
  end

  test "nothing matched", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search?q=zzzzqqq")
    assert html =~ "Nothing matched “zzzzqqq”"
    assert html =~ "search for a bill number"
  end

  test "stop words alone ask for more specific words", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search?q=the of")
    assert html =~ "Try more specific words."
  end

  test "an empty query shows a prompt", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/search")
    assert html =~ "Search for a bill"

    {:ok, _view, html} = live(conn, "/search?q[]=x&page[]=2")
    assert html =~ "Search for a bill"
  end

  test "the search box is on every page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/this-week")
    assert has_element?(view, "form#site-search[action='/search'][method='post'] input[name=q]")
    assert has_element?(view, "input#site-search-q[placeholder='Search bills and people']")
    assert has_element?(view, "form#site-search input[name=_csrf_token]")
  end
end
