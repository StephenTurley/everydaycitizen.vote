defmodule EverydayCitizen.Search.Query do
  @moduledoc """
  Decides what someone typed into the search box: nothing, an address or ZIP
  code (which belongs to the "your reps" lookup, never to search), or a search.

  The address rule errs toward treating a query as an address, so a street
  address is never run through search, logged as a query or put in a URL.
  """

  defstruct [:text, :key, :id_key, :number]

  @max_length 200

  @street_words ~w(st street ave avenue rd road dr drive ln lane blvd boulevard way ct court
                   pl place hwy highway pkwy parkway cir circle ter terrace trl trail pike
                   apt unit suite ste box route rte)

  @zip ~r/^\d{5}(-\d{4})?$/
  @street_start ~r/^\d{1,6}[a-z]?\s+\S/i
  @street_word ~r/\b(?:#{Enum.join(@street_words, "|")})\b/i
  @directional ~r/^\d{1,6}\s+(n|s|e|w|north|south|east|west)\s/i

  @doc "Classifies a raw query."
  def classify(nil), do: :empty

  def classify(raw) when is_binary(raw) do
    text = raw |> String.split() |> Enum.join(" ") |> String.slice(0, @max_length)

    cond do
      String.length(text) < 2 -> :empty
      address?(text) -> :address
      true -> {:search, build(text)}
    end
  end

  @doc """
  The name key: lower-case, runs of anything but letters and digits become one
  space, then a trailing " of <year>" and a trailing " act" are dropped. It
  mirrors the database function `ec_name_key`; a test keeps the two in step.
  """
  def name_key(string) when is_binary(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
    |> String.replace(~r/ of [0-9]{4}$/, "")
    |> String.replace(~r/ act$/, "")
    |> String.trim()
  end

  defp build(text) do
    %__MODULE__{
      text: text,
      key: name_key(text),
      id_key: id_key(text),
      number: if(text =~ ~r/^\d{1,5}$/, do: text)
    }
  end

  defp id_key(text) do
    squeezed = text |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
    if squeezed =~ ~r/^[a-z]{1,8}\d{1,5}$/, do: squeezed
  end

  defp address?(text) do
    text =~ @zip or
      (text =~ @street_start and (String.contains?(text, ",") or text =~ @street_word)) or
      text =~ @directional
  end
end
