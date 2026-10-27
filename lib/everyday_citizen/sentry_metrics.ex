defmodule EverydayCitizen.SentryMetrics do
  @moduledoc """
  Sends the site's counters to Sentry's metrics: `page.view` (by `page` and
  `visitor`, `EverydayCitizenWeb.PageViews`) and `crawler.blocked`
  (`EverydayCitizenWeb.AiCrawlers`). Only those labels are sent. Attached at
  start when Sentry is configured (production).
  """

  @events [[:everyday_citizen, :page_view], [:everyday_citizen, :crawler_blocked]]

  @doc "Starts sending the counters, when Sentry has a DSN."
  @spec attach() :: :ok
  def attach do
    if Application.get_env(:sentry, :dsn),
      do: :telemetry.attach_many("sentry-metrics", @events, &__MODULE__.handle_event/4, nil)

    :ok
  end

  @doc false
  def handle_event([:everyday_citizen, :page_view], _measures, meta, _config),
    do: Sentry.Metrics.count("page.view", 1, attributes: Map.take(meta, [:page, :visitor]))

  def handle_event([:everyday_citizen, :crawler_blocked], _measures, _meta, _config),
    do: Sentry.Metrics.count("crawler.blocked", 1)
end
