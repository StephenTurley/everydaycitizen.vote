defmodule TheFloor.Activity.Item do
  @moduledoc """
  One entry in a person's activity feed: a vote they cast (`:vote`, with their
  `option`), a bill they introduced (`:introduced`), progress on a bill they
  sponsored (`:moved`, with the `action`), or that bill becoming law
  (`:became_law`).
  """
  @enforce_keys [:kind, :date]
  defstruct [:kind, :date, :bill, :vote, :option, :action]

  @type t :: %__MODULE__{
          kind: :vote | :introduced | :moved | :became_law,
          date: Date.t(),
          bill: struct() | nil,
          vote: struct() | nil,
          option: String.t() | nil,
          action: struct() | nil
        }
end
