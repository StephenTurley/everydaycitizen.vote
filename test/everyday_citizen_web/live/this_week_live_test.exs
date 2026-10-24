defmodule EverydayCitizenWeb.ThisWeekLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EverydayCitizen.AccountsFixtures

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
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
      EverydayCitizen.Ingest.write(
        %EverydayCitizen.Ingest.Records.Event{
          jurisdiction: "federal",
          body_external_id: "senate",
          external_id: "floor-1",
          classification: "floor",
          title: "Consideration of S. 5",
          start_at: ~U[2026-10-26 14:00:00Z],
          bill_external_ids: ["119-s-5"],
          raw_bill_labels: ["H.R. 999999"],
          source: EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/e", "e")
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

  test "signed in, the Followed filter shows events on followed bills", %{conn: conn} do
    for {id, bills} <- [{"floor-1", ["119-s-5"]}, {"floor-2", []}] do
      {:ok, _} =
        EverydayCitizen.Ingest.write(
          %EverydayCitizen.Ingest.Records.Event{
            jurisdiction: "federal",
            body_external_id: "senate",
            external_id: id,
            classification: "floor",
            title: "Event #{id}",
            start_at: ~U[2026-10-26 14:00:00Z],
            bill_external_ids: bills,
            source: EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/#{id}", id)
          },
          nil
        )
    end

    user = user_fixture()
    scope = EverydayCitizen.Accounts.Scope.for_user(user)

    {:ok, _} =
      EverydayCitizen.Follows.follow(
        scope,
        {:bill, EverydayCitizen.Legislation.get_bill("federal", "119-s-5").id}
      )

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live(~p"/this-week?from=2026-10-26&followed=1")

    assert has_element?(view, ~s(a[aria-current="page"]), "Followed")
    assert render(view) =~ "Event floor-1"
    refute render(view) =~ "Event floor-2"
  end

  test "a pro forma session is defined in plain words; other items are not", %{conn: conn} do
    for {id, title, hour} <- [
          {"floor-pf", "Senate will meet in a pro forma session.", 14},
          {"floor-2", "Consideration of S. 5", 16}
        ] do
      {:ok, _} =
        EverydayCitizen.Ingest.write(
          %EverydayCitizen.Ingest.Records.Event{
            jurisdiction: "federal",
            body_external_id: "senate",
            external_id: id,
            classification: "floor",
            title: title,
            start_at: DateTime.new!(~D[2026-10-26], Time.new!(hour, 0, 0)),
            source: EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/e", "e")
          },
          nil
        )
    end

    {:ok, view, _html} = live(conn, ~p"/this-week?from=2026-10-26")

    assert [_] =
             view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("[data-term=pro-forma]")
             |> Enum.to_list()

    assert has_element?(view, "[data-term=pro-forma]", "brief formal meeting")
  end

  test "signed out, there is no Followed filter", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/this-week?from=2026-10-26&followed=1")
    refute has_element?(view, "a", "Followed")
  end
end
