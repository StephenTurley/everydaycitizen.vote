defmodule EverydayCitizenWeb.SearchControllerTest do
  use EverydayCitizenWeb.ConnCase, async: true

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    :ok
  end

  test "an address is never searched or put in a URL", %{conn: conn} do
    conn = post(conn, ~p"/search", %{"q" => "123 Main St"})
    assert redirected_to(conn) == "/"
    refute redirected_to(conn) =~ "Main"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "looks like an address"
  end

  test "a ZIP code is treated as an address", %{conn: conn} do
    conn = post(conn, ~p"/search", %{"q" => "50309"})
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "looks like an address"
  end

  test "a bill number goes straight to the bill", %{conn: conn} do
    assert redirected_to(post(conn, ~p"/search", %{"q" => "s5"})) == "/bills/119-s-5"
  end

  test "an ordinary query opens the results page", %{conn: conn} do
    assert redirected_to(post(conn, ~p"/search", %{"q" => "laken riley"})) ==
             "/search?q=laken+riley"
  end

  test "an empty query goes back where it came from, or home", %{conn: conn} do
    assert redirected_to(post(conn, ~p"/search", %{"q" => "  "})) == "/"
    assert redirected_to(post(conn, ~p"/search", %{"q" => ["x"]})) == "/"

    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/this-week?week=2026-01-19")
      |> post(~p"/search", %{"q" => ""})

    assert redirected_to(conn) == "/this-week?week=2026-01-19"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == nil
  end

  test "a referer on another site is not followed", %{conn: conn} do
    conn =
      conn
      |> put_req_header("referer", "https://evil.test/phish")
      |> post(~p"/search", %{"q" => ""})

    assert redirected_to(conn) == "/"
  end

  test "q is filtered from logs" do
    # Phoenix compiles the list at boot, so check what the logger makes of it
    assert Phoenix.Logger.filter_values(%{"q" => "123 Main St"}) == %{"q" => "[FILTERED]"}
  end
end
