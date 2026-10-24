defmodule TheFloorWeb.ThisWeekLiveTest do
  use TheFloorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    TheFloor.FloorFixtures.iowa!()
    :ok
  end

  test "previous and next week links keep the My reps choice", %{conn: conn} do
    conn = init_test_session(conn, %{district: "IA-1"})
    {:ok, view, _html} = live(conn, ~p"/this-week?from=2026-10-26&mine=1")

    assert has_element?(
             view,
             ~s(a[aria-label="Previous week"][href="/this-week?from=2026-10-19&mine=1"])
           )

    assert has_element?(
             view,
             ~s(a[aria-label="Next week"][href="/this-week?from=2026-11-02&mine=1"])
           )

    assert render(view) =~
             "Bills your reps sponsor or cosponsor, and meetings of committees they sit on."
  end

  test "an empty week says so", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/this-week?from=2026-10-26")
    assert html =~ "Nothing scheduled"
  end

  test "lists the week's events with their bills; My reps appears with a saved district", %{
    conn: conn
  } do
    {:ok, _} =
      TheFloor.Ingest.write(
        %TheFloor.Ingest.Records.Event{
          jurisdiction: "federal",
          body_external_id: "senate",
          external_id: "floor-1",
          classification: "floor",
          title: "Consideration of S. 5",
          start_at: ~U[2026-10-26 14:00:00Z],
          bill_external_ids: ["119-s-5"],
          raw_bill_labels: ["H.R. 999999"],
          source: TheFloor.Ingest.Records.SourceRef.new("https://x.test/e", "e")
        },
        nil
      )

    conn = init_test_session(conn, %{district: "IA-1"})
    {:ok, view, html} = live(conn, ~p"/this-week?from=2026-10-26")

    assert html =~ "Consideration of S. 5"
    assert has_element?(view, ~s(a[href="/bills/119-s-5"]))
    assert html =~ "H.R. 999999"
    assert has_element?(view, "a", "My reps")
  end
end
