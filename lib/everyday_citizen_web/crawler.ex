defmodule EverydayCitizenWeb.Crawler do
  @moduledoc """
  Whether a page is being fetched by a crawler, link previewer or script rather
  than a person, from its user agent (the socket's `:user_agent` connect info,
  endpoint). Crawlers see summaries already written but never start new ones;
  clients that pass as browsers are left to the daily budget and visitor limit.
  """
  import Phoenix.LiveView, only: [get_connect_info: 2]

  @agents ~r/bot\b|bot\/|crawl|spider|slurp|facebookexternalhit|preview|headless|curl|wget|python|go-http|java\/|libwww|scrapy|httpclient|okhttp|axios|node-fetch/i

  @spec crawler?(Phoenix.LiveView.Socket.t()) :: boolean()
  def crawler?(socket), do: user_agent?(get_connect_info(socket, :user_agent))

  @doc "Whether a user agent is a crawler's. None at all (only tests send none) is not."
  @spec user_agent?(String.t() | nil) :: boolean()
  def user_agent?(nil), do: false
  def user_agent?(agent), do: String.trim(agent) == "" or Regex.match?(@agents, agent)
end
