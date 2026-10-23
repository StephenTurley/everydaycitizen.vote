defmodule TheFloor.Adapters.Federal.Sessions do
  @moduledoc """
  Resolves which session numbers of a congress a list job covers, and folds a
  per-session sync over them, halting on the first error.
  """
  alias TheFloor.Legislature

  @doc "The given session, or every stored child session of the congress."
  @spec numbers(integer(), integer() | nil) :: [integer()]
  def numbers(_congress, session) when not is_nil(session), do: [session]

  def numbers(congress, nil) do
    "federal"
    |> Legislature.child_sessions("#{congress}")
    |> Enum.map(fn %{identifier: identifier} ->
      identifier |> String.split("-") |> List.last() |> String.to_integer()
    end)
  end

  @doc "Runs `fun.(session)` per session; stats are keyed `\"congress-session\"`."
  @spec reduce([integer()], integer(), (integer() -> {:ok, map()} | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def reduce(sessions, congress, fun) do
    Enum.reduce_while(sessions, {:ok, %{}}, fn session, {:ok, stats} ->
      case fun.(session) do
        {:ok, session_stats} ->
          {:cont, {:ok, Map.put(stats, "#{congress}-#{session}", session_stats)}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end
end
