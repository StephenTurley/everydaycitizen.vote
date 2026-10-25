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

  test "a state and ZIP code is an address when no bill has that number", %{conn: conn} do
    for q <- ["IA 50309", "ia50309"] do
      conn = post(conn, ~p"/search", %{"q" => q})
      assert redirected_to(conn) == "/", q
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "looks like an address"
    end
  end

  test "a five-digit bill number that is stored goes straight to the bill", %{conn: conn} do
    {:ok, _} =
      EverydayCitizen.Ingest.write(
        %EverydayCitizen.Ingest.Records.Bill{
          jurisdiction: "federal",
          session_identifier: "119",
          external_id: "119-hr-10545",
          identifier: "H.R. 10545",
          classification: "bill",
          title: "A Long-Numbered Act",
          introduced_on: ~D[2026-01-03],
          source: EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/b", "b")
        },
        nil
      )

    assert redirected_to(post(conn, ~p"/search", %{"q" => "hr10545"})) == "/bills/119-hr-10545"
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

  test "the header form's own CSRF token is accepted, with ConnTest's bypass off", %{conn: conn} do
    conn = get(conn, ~p"/this-week")

    [_, token] =
      Regex.run(
        ~r/<form[^>]*id="site-search".*?name="_csrf_token"[^>]*value="([^"]+)"/s,
        html_response(conn, 200)
      )

    fresh = fn -> conn |> recycle() |> put_private(:plug_skip_csrf_protection, false) end

    posted = post(fresh.(), ~p"/search", %{"_csrf_token" => token, "q" => "laken riley"})
    assert redirected_to(posted) == "/search?q=laken+riley"

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(fresh.(), ~p"/search", %{"q" => "laken riley"})
    end
  end

  test "q is filtered from logs" do
    # Phoenix compiles the list at boot, so check what the logger makes of it
    assert Phoenix.Logger.filter_values(%{"q" => "123 Main St"}) == %{"q" => "[FILTERED]"}
  end
end
