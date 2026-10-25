defmodule EverydayCitizenWeb.AiBillSummary do
  @moduledoc """
  A bill's plain-English summary for a LiveView: shown from the cache, or asked
  for once the page is live (listening first on `Summaries.ai_topic/2`, so one
  finished in between is not missed) inside the visitor's hourly limit. Crawlers
  are shown cached ones only and never start one. The socket needs `crawler` and
  `remote_ip` assigns; results arrive as `{:ai_summary, "bill", subject, result}`.
  """
  import Phoenix.LiveView, only: [connected?: 1]

  alias EverydayCitizen.{RateLimit, Summaries}
  alias EverydayCitizen.Summaries.{Claude, Inputs}

  @hour :timer.hours(1)

  @type state :: {:ok, String.t()} | :loading | :limited | :paused | :unavailable | atom()

  @doc "`{subject, state}` for the bill's summary, or nil when there is none to show."
  @spec load(Phoenix.LiveView.Socket.t(), map()) :: {String.t(), state()} | nil
  def load(socket, bill) do
    with true <- Claude.enabled?(),
         {subject, input} <- Inputs.bill(bill),
         state when state != :none <- state(socket, subject, input) do
      {subject, state}
    else
      _ -> nil
    end
  end

  defp state(socket, subject, input) do
    cond do
      summary = Summaries.get_ai(:bill, subject, input) ->
        {:ok, summary.summary}

      socket.assigns.crawler ->
        :none

      not connected?(socket) ->
        :loading

      true ->
        Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, Summaries.ai_topic(:bill, subject))

        if RateLimit.hit({:summaries, socket.assigns.remote_ip}, Summaries.visitor_limit(), @hour) ==
             :limited,
           do: :limited,
           else: requested(Summaries.request_ai(:bill, subject, input))
    end
  end

  @doc "The state for a summary job's result."
  @spec result_state({:ok, String.t()} | {:error, term()}) :: state()
  def result_state({:ok, text}), do: {:ok, text}
  def result_state({:error, :paused}), do: :paused
  def result_state({:error, _}), do: :unavailable

  @doc "The state for what asking for a summary returned."
  @spec requested(term()) :: state()
  def requested({:cached, summary}), do: {:ok, summary.summary}
  def requested(:queued), do: :loading
  def requested(other), do: other
end
