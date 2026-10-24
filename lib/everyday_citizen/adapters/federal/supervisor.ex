defmodule EverydayCitizen.Adapters.Federal.Supervisor do
  @moduledoc "Starts the per-source rate limiters used by the federal adapter."
  use Supervisor

  alias EverydayCitizen.Ingest.RateLimiter

  @defaults [
    congress_gov: 750,
    govinfo: 1000,
    house_docs: 1000,
    senate_gov: 2000,
    voteview: 2000,
    census: 1000
  ]

  def start_link(arg), do: Supervisor.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  def init(_arg) do
    intervals = Application.get_env(:everyday_citizen, :federal_rate_limits, @defaults)

    children =
      for {name, default} <- @defaults do
        {RateLimiter, name: name, interval_ms: Keyword.get(intervals, name, default)}
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
