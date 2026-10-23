defmodule TheFloor.Ingest.RateLimiter do
  @moduledoc """
  Named client-side rate limiter. `acquire/1` blocks the caller until at least
  `interval_ms` have passed since the previous grant for that limiter.
  """
  use GenServer

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    interval = Keyword.fetch!(opts, :interval_ms)
    GenServer.start_link(__MODULE__, interval, name: name)
  end

  def child_spec(opts) do
    %{id: Keyword.fetch!(opts, :name), start: {__MODULE__, :start_link, [opts]}}
  end

  @spec acquire(atom()) :: :ok
  def acquire(name), do: GenServer.call(name, :acquire, :infinity)

  @impl true
  def init(interval), do: {:ok, %{interval: interval, last: nil}}

  @impl true
  def handle_call(:acquire, _from, %{interval: interval, last: last} = state) do
    now = System.monotonic_time(:millisecond)
    wait = if last, do: max(last + interval - now, 0), else: 0
    if wait > 0, do: Process.sleep(wait)
    {:reply, :ok, %{state | last: now + wait}}
  end
end
