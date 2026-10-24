defmodule EverydayCitizen.Adapters.Federal.VoteSupport do
  @moduledoc "Helpers shared by the House and Senate roll-call normalizers."

  @negative ~r/rejected|failed|not (sustained|agreed|confirmed|passed|guilty)|defeated|not invoked/i
  @positive ~r/agreed to|passed|confirmed|adopted|sustained|invoked|guilty|ratified/i

  @doc "Reads a result string as passed (true), failed (false) or undetermined (nil)."
  @spec passed(String.t() | nil) :: boolean() | nil
  def passed(nil), do: nil

  def passed(result) do
    cond do
      Regex.match?(@negative, result) -> false
      Regex.match?(@positive, result) -> true
      true -> nil
    end
  end

  @doc "Converts a naive America/New_York wall-clock time to UTC."
  @spec eastern_to_utc(NaiveDateTime.t()) :: DateTime.t()
  def eastern_to_utc(%NaiveDateTime{} = naive) do
    local =
      case DateTime.from_naive(naive, "America/New_York") do
        {:ok, dt} -> dt
        {:ambiguous, first, _second} -> first
        {:gap, _before, after_gap} -> after_gap
      end

    DateTime.shift_zone!(local, "Etc/UTC")
  end

  @doc "Maps an empty string to nil."
  @spec blank_to_nil(String.t()) :: String.t() | nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(string), do: string
end
