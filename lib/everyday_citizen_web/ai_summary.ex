defmodule EverydayCitizenWeb.AiSummary do
  @moduledoc """
  How a LiveView gets a plain-English AI summary, the same way on every page:
  the cached one; else none for a crawler (which never starts one); "loading"
  before the page is live; past the visitor's hourly limit, "limited"; else it
  is asked for. A page listens on the summary's topic before asking, so one
  finished in between is not missed, and stops listening when what it shows
  changes. Results arrive as `{:ai_summary, kind, subject, result}`. The socket
  needs `crawler` and `remote_ip` assigns.
  """
  import Phoenix.LiveView, only: [connected?: 1]
  import Phoenix.Component, only: [assign: 3]

  alias EverydayCitizen.{RateLimit, Summaries}
  alias EverydayCitizen.Summaries.{Claude, Inputs}

  @hour :timer.hours(1)
  @repo_url "https://github.com/StephenTurley/everydaycitizen.vote/blob/main/"

  @type state :: {:ok, String.t()} | :loading | :limited | :paused | :unavailable | atom()

  @doc """
  The state to show, given the cached summary (or nil) and a function that asks
  for one, called only when nothing stands in the way. `:none` means show
  nothing (a crawler, with nothing cached).
  """
  @spec state(Phoenix.LiveView.Socket.t(), %{summary: String.t()} | nil, (-> term())) ::
          state() | :none
  def state(socket, cached, request) do
    cond do
      cached -> {:ok, cached.summary}
      socket.assigns.crawler -> :none
      not connected?(socket) -> :loading
      limited?(socket) -> :limited
      true -> requested(request.())
    end
  end

  defp limited?(socket),
    do:
      RateLimit.hit({:summaries, socket.assigns.remote_ip}, Summaries.visitor_limit(), @hour) ==
        :limited

  @doc """
  Assigns `key` the summary of `kind` for `{subject, input}` as `{subject, state}`,
  or nil when there is none to show; stops listening on the topic `key` held
  before, and listens while the summary is being written.
  """
  @spec load(Phoenix.LiveView.Socket.t(), atom(), atom(), {String.t(), String.t()} | nil) ::
          Phoenix.LiveView.Socket.t()
  def load(socket, key, kind, subject_input) do
    socket = unwatch(socket, key)

    with {subject, input} <- subject_input,
         true <- Claude.enabled?(),
         {state, topic} when state != :none <- lookup(socket, kind, subject, input) do
      socket
      |> assign(key, {subject, state})
      |> watch(key, topic)
    else
      _ -> assign(socket, key, nil)
    end
  end

  @doc "`{subject, state}` for a bill's summary, or nil when there is none to show (home page)."
  @spec load(Phoenix.LiveView.Socket.t(), map()) :: {String.t(), state()} | nil
  def load(socket, bill) do
    with true <- Claude.enabled?(),
         {subject, input} <- Inputs.bill(bill),
         {state, _topic} when state != :none <- lookup(socket, :bill, subject, input) do
      {subject, state}
    else
      _ -> nil
    end
  end

  # A live page with nothing cached listens before asking, so a result is not
  # missed (also when the visitor is past the limit and another's request writes
  # it); returns the topic it listens on, or nil.
  defp lookup(socket, kind, subject, input) do
    cached = Summaries.get_ai(kind, subject, input)
    topic = Summaries.ai_topic(kind, subject)
    listen? = is_nil(cached) and not socket.assigns.crawler and connected?(socket)
    if listen?, do: Phoenix.PubSub.subscribe(EverydayCitizen.PubSub, topic)

    {state(socket, cached, fn -> Summaries.request_ai(kind, subject, input) end),
     if(listen?, do: topic)}
  end

  @doc "Shows a finished summary under `key`, if `key` still shows that subject."
  @spec put_result(Phoenix.LiveView.Socket.t(), atom(), String.t(), term()) ::
          Phoenix.LiveView.Socket.t()
  def put_result(socket, key, subject, result) do
    case socket.assigns[key] do
      {^subject, _state} -> assign(socket, key, {subject, result_state(result)})
      _other -> socket
    end
  end

  defp watch(socket, _key, nil), do: socket

  defp watch(socket, key, topic),
    do: assign(socket, :ai_topics, Map.put(socket.assigns[:ai_topics] || %{}, key, topic))

  defp unwatch(socket, key) do
    topics = socket.assigns[:ai_topics] || %{}
    if topic = topics[key], do: Phoenix.PubSub.unsubscribe(EverydayCitizen.PubSub, topic)
    assign(socket, :ai_topics, Map.delete(topics, key))
  end

  @doc "What a \"Report a problem\" form under a summary sends with the report."
  @spec report(map(), atom(), String.t(), String.t() | nil) :: map()
  def report(assigns, kind, subject, page \\ nil) do
    %{
      kind: to_string(kind),
      subject: subject,
      prompt_version: Summaries.cache_version(kind),
      page: page || assigns[:path],
      user: assigns.current_scope && assigns.current_scope.user,
      remote_ip: assigns.remote_ip
    }
  end

  @doc "The published prompt for a kind of summary, on GitHub."
  @spec prompt_url(atom()) :: String.t()
  def prompt_url(kind), do: @repo_url <> Claude.prompt_path(kind)

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
