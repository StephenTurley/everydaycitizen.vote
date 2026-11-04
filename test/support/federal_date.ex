defmodule EverydayCitizen.FederalDate do
  @moduledoc """
  Pins the date the sitting congress is worked out from, for one test (the
  test module must not be async: the setting is global).
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  @spec on(Date.t()) :: :ok
  def on(%Date{} = date) do
    previous = Application.fetch_env!(:everyday_citizen, :federal)
    Application.put_env(:everyday_citizen, :federal, Keyword.put(previous, :today, date))
    on_exit(fn -> Application.put_env(:everyday_citizen, :federal, previous) end)
  end

  @doc "Adds a Census map for a congress for one test."
  @spec with_vintage(pos_integer(), String.t()) :: :ok
  def with_vintage(congress, vintage) do
    previous = Application.fetch_env!(:everyday_citizen, :federal)
    vintages = Map.put(previous[:census_vintages], congress, vintage)

    Application.put_env(
      :everyday_citizen,
      :federal,
      Keyword.put(previous, :census_vintages, vintages)
    )

    on_exit(fn -> Application.put_env(:everyday_citizen, :federal, previous) end)
  end
end
