defmodule EverydayCitizenWeb.SearchRateLimitTest do
  # changes the app's search limit, so not async
  use EverydayCitizenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    EverydayCitizen.FloorFixtures.iowa!()
    limit = Application.get_env(:everyday_citizen, :search)
    Application.put_env(:everyday_citizen, :search, per_minute: 1)
    on_exit(fn -> Application.put_env(:everyday_citizen, :search, limit) end)

    ip = "203.0.113.#{System.unique_integer([:positive])}"
    {:ok, conn: Plug.Conn.put_req_header(conn, "x-forwarded-for", ip)}
  end

  test "past the limit a visitor is asked to wait, and no query runs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/search?q=laken riley")
    assert has_element?(view, "section[aria-label='Bills with this name']")

    test_pid = self()
    handler = "search-rate-limit-#{inspect(test_pid)}"

    :telemetry.attach(
      handler,
      [:everyday_citizen, :repo, :query],
      fn _event, _measure, _meta, _ -> send(test_pid, {:query, self()}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    html = render_patch(view, ~p"/search?q=grassley")
    assert html =~ "Too many searches. Wait a minute and try again."
    refute html =~ "Bills with this name"
    refute html =~ "Nothing matched"

    view_pid = view.pid
    refute_received {:query, ^view_pid}
  end

  test "a second visitor is not limited by the first", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/search?q=laken riley")

    other =
      Plug.Conn.put_req_header(
        build_conn(),
        "x-forwarded-for",
        "198.51.100.#{System.unique_integer([:positive])}"
      )

    {:ok, view, _html} = live(other, ~p"/search?q=laken riley")
    assert has_element?(view, "section[aria-label='Bills with this name']")
  end
end
