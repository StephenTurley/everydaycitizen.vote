defmodule EverydayCitizen.NodeHeartbeat do
  @moduledoc """
  Records this node's heartbeat every 30 seconds and, every minute, releases
  jobs left executing by nodes that stopped (`EverydayCitizen.ObanRescue`).
  Started after Oban, in production only (`:node_heartbeat` config).
  """
  use GenServer

  require Logger

  alias EverydayCitizen.ObanRescue

  @beat_every :timer.seconds(30)
  @sweep_every :timer.minutes(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    node = Oban.config().node
    send(self(), :beat)
    Process.send_after(self(), :sweep, @sweep_every)
    {:ok, node}
  end

  @impl true
  def handle_info(:beat, node) do
    safely(fn -> ObanRescue.beat(node) end)
    Process.send_after(self(), :beat, @beat_every)
    {:noreply, node}
  end

  def handle_info(:sweep, node) do
    safely(fn ->
      case ObanRescue.release_orphans() do
        0 -> :ok
        n -> Logger.info("released #{n} job(s) left executing by stopped nodes")
      end
    end)

    Process.send_after(self(), :sweep, @sweep_every)
    {:noreply, node}
  end

  # a database hiccup must not take this process (and the app) down
  defp safely(fun) do
    fun.()
  rescue
    error -> Logger.warning("node heartbeat: #{Exception.message(error)}")
  end
end
