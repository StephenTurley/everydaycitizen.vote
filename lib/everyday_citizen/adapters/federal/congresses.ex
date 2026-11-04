defmodule EverydayCitizen.Adapters.Federal.Congresses do
  @moduledoc """
  Which congress sits on a date. A congress begins on Jan 3 of an odd year
  (20th Amendment; the 120th on Jan 3, 2027), so the number comes from the date,
  in Eastern time. Bill sync keeps listing the previous congress for 30 days
  after the change, so bills passed in December still get their signing or veto.
  Tests pin the date with `config :everyday_citizen, :federal, today: ~D[...]`.
  """
  alias EverydayCitizen.Adapters.Federal.VoteSupport
  alias EverydayCitizen.Clock

  @grace_days 30

  @doc "Today in Eastern time, or the configured date in tests."
  @spec today() :: Date.t()
  def today do
    Application.fetch_env!(:everyday_citizen, :federal)[:today] ||
      Clock.today(VoteSupport.time_zone())
  end

  @doc "The congress sitting today."
  @spec current() :: pos_integer()
  def current, do: current(today())

  @doc "The congress sitting on `date`."
  @spec current(Date.t()) :: pos_integer()
  def current(%Date{year: year} = date) do
    first_year = if rem(year, 2) == 1, do: year, else: year - 1
    number = div(first_year - 1789, 2) + 1
    if Date.before?(date, start_date(number)), do: number - 1, else: number
  end

  @doc "The day a congress begins (Jan 3; valid from the 74th)."
  @spec start_date(pos_integer()) :: Date.t()
  def start_date(number), do: Date.new!(1789 + 2 * (number - 1), 1, 3)

  @doc "The congresses bill sync lists today."
  @spec syncing() :: [pos_integer()]
  def syncing, do: syncing(today())

  @doc "The sitting congress, then the previous one for #{@grace_days} days after the change."
  @spec syncing(Date.t()) :: [pos_integer()]
  def syncing(%Date{} = date) do
    number = current(date)

    if Date.diff(date, start_date(number)) < @grace_days,
      do: [number, number - 1],
      else: [number]
  end
end
