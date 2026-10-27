defmodule EverydayCitizenWeb.PageViewsTest do
  use EverydayCitizenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @googlebot "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
  @gptbot "Mozilla/5.0 (compatible; GPTBot/1.4; +https://openai.com/gptbot)"

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    test = self()
    id = "page-views-#{inspect(test)}"

    :telemetry.attach_many(
      id,
      [[:everyday_citizen, :page_view], [:everyday_citizen, :crawler_blocked]],
      fn event, _measures, meta, _ ->
        if test in [self() | Process.get(:"$callers", [])], do: send(test, {event, meta})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
    :ok
  end

  defp views do
    receive do
      {[:everyday_citizen, :page_view], meta} -> [meta | views()]
    after
      0 -> []
    end
  end

  test "a person's view counts once, when the page connects", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/bills/119-s-5")
    assert views() == [%{page: "bill", visitor: "person"}]
  end

  test "each kind of page has its own name, and nothing else is sent", %{conn: conn} do
    for {path, page} <- [
          {"/", "home"},
          {"/this-week", "this_week"},
          {"/reps/IA-1", "reps"},
          {"/search?q=tax", "search"}
        ] do
      {:ok, _view, _html} = live(conn, path)
      assert views() == [%{page: page, visitor: "person"}]
    end
  end

  test "moving within a page (another section) is not a new view", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")
    _ = views()
    render_patch(view, ~p"/bills/119-s-5?section=0")
    assert views() == []
  end

  test "a crawler's view counts on its render", %{conn: conn} do
    conn |> put_req_header("user-agent", @googlebot) |> get(~p"/bills/119-s-5")
    assert views() == [%{page: "bill", visitor: "crawler"}]
  end

  test "a person's first render alone is not counted", %{conn: conn} do
    conn |> put_req_header("user-agent", "Mozilla/5.0 (Macintosh)") |> get(~p"/bills/119-s-5")
    assert views() == []
  end

  test "a turned-away AI crawler is counted as blocked, not as a view", %{conn: conn} do
    conn |> put_req_header("user-agent", @gptbot) |> get(~p"/bills/119-s-5")
    assert_received {[:everyday_citizen, :crawler_blocked], %{agent: "GPTBot"}}
    assert views() == []
  end
end
