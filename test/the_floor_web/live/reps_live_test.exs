defmodule TheFloorWeb.RepsLiveTest do
  use TheFloorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @census "test/support/fixtures/federal/census"
  @address "400 S Clinton St, Iowa City, IA 52240"

  setup do
    people = TheFloor.FloorFixtures.iowa!()

    {:ok, _} =
      TheFloor.Ingest.write(
        %TheFloor.Ingest.Records.PostalDistricts{
          jurisdiction: "federal",
          rows: [
            %{postal_code: "52240", district_key: "IA-1", land_share: 1.0},
            %{postal_code: "52031", district_key: "IA-1", land_share: 0.947},
            %{postal_code: "52031", district_key: "IA-2", land_share: 0.053}
          ],
          source: TheFloor.Ingest.Records.SourceRef.new("https://x.test/reps-live-postal", "z")
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
    Req.Test.stub(TheFloor.Federal, fn conn ->
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
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, 500, "busy") end)
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

  test "picking a rep and a filter patches the page", %{conn: conn, ernst: e} do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1")

    view |> element(~s(a[href="/reps/IA-1?rep=#{e.id}"])) |> render_click()
    assert_patch(view, "/reps/IA-1?rep=#{e.id}")
    assert render(view) =~ "Introduced a bill"

    html = view |> element("a", "Votes") |> render_click()
    assert html =~ "Voted Nay"
    refute html =~ "Introduced a bill"
  end

  test "items link to their bill pages", %{conn: conn, grassley: g} do
    {:ok, view, _html} = live(conn, ~p"/reps/IA-1?rep=#{g.id}")
    assert has_element?(view, ~s(a[href="/bills/119-s-5"]))
  end

  test "a rep with nothing in the filter sees Nothing yet", %{conn: conn, miller_meeks: m} do
    {:ok, _view, html} = live(conn, ~p"/reps/IA-1?rep=#{m.id}")
    assert html =~ "Nothing yet"
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
    TheFloor.Repo.update_all(TheFloor.Votes.Vote,
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
    Req.Test.stub(TheFloor.Federal, fn _conn -> flunk("no lookup expected") end)
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
    Req.Test.stub(TheFloor.Federal, fn _conn -> flunk("no address lookup expected") end)
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
end
