defmodule EverydayCitizen.RateLimit do
  @moduledoc """
  Fixed-window counters in memory (one machine): `hit(key, limit, window_ms)`
  is `:ok` while fewer than `limit` hits fell in the current window, else
  `:limited`. Used to cap sign-in emails per visitor. Counters reset on
  restart, which is acceptable for abuse limits; old windows are pruned.
  """
  use GenServer

  @table __MODULE__
  @prune_every :timer.minutes(10)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec hit(term(), pos_integer(), pos_integer()) :: :ok | :limited
  def hit(key, limit, window_ms) do
    window = div(System.system_time(:millisecond), window_ms)

    count =
      :ets.update_counter(
        @table,
        {key, window},
        1,
        {{key, window}, 0, window_end(window, window_ms)}
      )

    if count <= limit, do: :ok, else: :limited
  end

  @doc "Clears every counter (tests)."
  def reset, do: :ets.delete_all_objects(@table)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    Process.send_after(self(), :prune, @prune_every)
    {:ok, nil}
  end

  @impl true
  def handle_info(:prune, state) do
    now = System.system_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    Process.send_after(self(), :prune, @prune_every)
    {:noreply, state}
  end

  defp window_end(window, window_ms), do: (window + 1) * window_ms
end
