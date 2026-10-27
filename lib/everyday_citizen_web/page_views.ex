defmodule EverydayCitizenWeb.PageViews do
  @moduledoc """
  Counts page views, as `[:everyday_citizen, :page_view]` telemetry events with
  only `%{page, visitor}`: the kind of page (`"bill"`, `"home"`, ...) and
  `"person"` or `"crawler"`. A person's view counts when the live page connects
  (only a browser does), so a page that renders and then connects counts once;
  moving within a page (a section, a version) is not a new view. A crawler,
  which never connects, counts on its render. Nothing else is recorded: no path,
  bill, district, address or anything about the visitor.

  `EverydayCitizen.SentryMetrics` sends the counts to Sentry. An `on_mount` hook
  on every LiveView (`EverydayCitizenWeb.live_view/0`).
  """
  alias EverydayCitizenWeb.Crawler

  @pages %{
    EverydayCitizenWeb.HomeLive => "home",
    EverydayCitizenWeb.BillLive => "bill",
    EverydayCitizenWeb.RepsLive => "reps",
    EverydayCitizenWeb.PersonLive => "person",
    EverydayCitizenWeb.SearchLive => "search",
    EverydayCitizenWeb.ThisWeekLive => "this_week",
    EverydayCitizenWeb.FeedbackLive => "feedback",
    EverydayCitizenWeb.UserLive.Settings => "settings",
    EverydayCitizenWeb.UserLive.Login => "sign_in",
    EverydayCitizenWeb.UserLive.Confirmation => "sign_in"
  }

  def on_mount(:default, _params, _session, socket) do
    cond do
      Phoenix.LiveView.connected?(socket) -> count(socket.view, "person")
      Crawler.crawler?(socket) -> count(socket.view, "crawler")
      true -> :ok
    end

    {:cont, socket}
  end

  defp count(view, visitor) do
    :telemetry.execute([:everyday_citizen, :page_view], %{count: 1}, %{
      page: Map.get(@pages, view, "other"),
      visitor: visitor
    })
  end
end
