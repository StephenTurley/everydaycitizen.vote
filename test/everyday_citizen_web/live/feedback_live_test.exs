defmodule EverydayCitizenWeb.FeedbackLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest

  alias EverydayCitizen.Feedback.Report
  alias EverydayCitizen.Repo

  test "the site feedback page takes a note and thanks the sender", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/feedback")

    view
    |> form("#feedback-site form", report: %{reason: "other", note: "Love it."})
    |> render_submit()

    assert has_element?(view, "#feedback-site", "Thanks")
    assert [%Report{kind: "site", note: "Love it.", page: "/feedback"}] = Repo.all(Report)
  end

  test "every page links to it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/this-week")
    assert has_element?(view, ~s(footer a[href="/feedback"]), "Send feedback")
  end

  test "a filled-in trap field is thanked but not stored", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/feedback")

    view
    |> form("#feedback-site form", report: %{reason: "other", note: "buy", website: "x.biz"})
    |> render_submit()

    assert has_element?(view, "#feedback-site", "Thanks")
    assert Repo.all(Report) == []
  end
end
