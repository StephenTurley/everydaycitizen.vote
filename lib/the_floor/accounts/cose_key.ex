defmodule TheFloor.Accounts.CoseKey do
  @moduledoc """
  Ecto type for a WebAuthn COSE public key: the map of integer labels to
  integers or binaries that `Wax` returns at registration and expects at
  authentication.

  Stored as Erlang External Term Format and decoded with `:safe`, so a
  tampered row cannot mint atoms; anything that is not a well-formed key map
  fails to load.
  """
  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(%{} = key), do: if(valid?(key), do: {:ok, key}, else: :error)
  def cast(_), do: :error

  @impl true
  def dump(%{} = key), do: if(valid?(key), do: {:ok, :erlang.term_to_binary(key)}, else: :error)
  def dump(_), do: :error

  @impl true
  def load(bin) when is_binary(bin) do
    case :erlang.binary_to_term(bin, [:safe]) do
      %{} = key -> if valid?(key), do: {:ok, key}, else: :error
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  def load(_), do: :error

  defp valid?(key) do
    map_size(key) > 0 and
      Enum.all?(key, fn {k, v} -> is_integer(k) and (is_integer(v) or is_binary(v)) end)
  end
end
