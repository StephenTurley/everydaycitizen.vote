defmodule TheFloorWeb.RepsLiveTest do
  use TheFloorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @census "test/support/fixtures/federal/census"
  @address "400 S Clinton St, Iowa City, IA 52240"

  setup do
    people = TheFloor.FloorFixtures.iowa!()
    {:ok, people}
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
             view |> form("#address-form", address: @address) |> render_submit()

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
    html = view |> form("#address-form", address: "99 Nowhere Rd") |> render_submit()

    assert html =~ "We couldn&#39;t find that address"
    assert html =~ ~s(value="99 Nowhere Rd")
  end

  test "a failing lookup service says so", %{conn: conn} do
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, 500, "busy") end)
    {:ok, view, _html} = live(conn, ~p"/")
    html = view |> form("#address-form", address: @address) |> render_submit()
    assert html =~ "Address lookup is unavailable"
  end

  test "the reps page shows the three reps, the first selected", %{conn: conn, grassley: g} do
    {:ok, view, html} = live(conn, ~p"/reps/IA-1")

    for name <- ["Chuck Grassley", "Joni Ernst", "Mariannette Miller-Meeks"],
        do: assert(html =~ name)

    assert has_element?(view, ~s(a[aria-pressed="true"][href="/reps/IA-1?rep=#{g.id}"]))
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
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ ~s(method="post")
    assert html =~ ~s(action="/district")

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
    assert view |> form("#address-form", address: "  ") |> render_submit() =~ "Enter your address"
  end

  test "a district key that names no place is not saved", %{conn: conn} do
    conn = get(conn, "/district/nonsense")
    assert redirected_to(conn) == "/"
    refute get_session(conn, :district)
  end
end
