defmodule EverydayCitizen.Search.Query do
  @moduledoc """
  Decides what someone typed into the search box: nothing, an address or ZIP
  code (which belongs to the "your reps" lookup, never to search), or a search.

  The address rule errs toward treating a query as an address, so a street
  address is never run through search, logged as a query or put in a URL.
  """

  defstruct [:text, :key, :id_key, :number]

  @type t :: %__MODULE__{
          text: String.t(),
          key: String.t(),
          id_key: String.t() | nil,
          number: String.t() | nil
        }

  @max_length 200

  @street_words ~w(st street ave avenue rd road dr drive ln lane blvd boulevard way ct court
                   pl place hwy highway pkwy parkway cir circle ter terrace trl trail pike
                   apt unit suite ste box route rte)

  # every kind of Unicode space, the zero-width ones included
  @spaces ~r/[\s\p{Z}\x{200B}\x{FEFF}]+/u
  # a ZIP code, ZIP+4, or ZIP+4 without its hyphen
  @zip ~r/\b(?:\d{5}(-\d{4})?|\d{9})\b/u
  @po_box ~r/\bp\.?\s*o\.?\s*box\b/iu
  @street_start ~r/^\d{1,6}[a-z]?\s\S/iu
  # anywhere after the street number, so "1 way forward" counts too: the rule
  # errs toward address
  @street_word ~r/\b(?:#{Enum.join(@street_words, "|")})\b/iu
  # the whole query is one number with its letters: "hr10000", "H.R. 10000",
  # "H. Res. 10000"; words without periods ("my zip 50309") are not
  @bill_number ~r/^(?:[a-z]+\.\s?)*[a-z]+\.?\s?\d{1,5}$/iu
  @directional ~r/^\d{1,6}\s(n|s|e|w|north|south|east|west)\s/iu

  @doc "Classifies a raw query."
  def classify(nil), do: :empty

  def classify(raw) when is_binary(raw) do
    text =
      raw
      |> String.replace(@spaces, " ")
      |> String.trim()
      |> String.slice(0, @max_length)
      |> String.trim_trailing()

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
    |> String.replace(~r/ of [0-9]{4}$/u, "")
    |> String.replace(~r/ act$/u, "")
    |> String.trim()
  end

  defp build(text) do
    %__MODULE__{
      text: text,
      key: name_key(text),
      id_key: id_key(text),
      number: if(text =~ ~r/^[0-9]{1,5}$/u, do: text)
    }
  end

  defp id_key(text) do
    squeezed = text |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]+/u, "")
    if squeezed =~ ~r/^[a-z]{1,8}[0-9]{1,5}$/u, do: squeezed
  end

  # A ZIP code anywhere makes the query an address, unless the whole query is
  # a bill number ("H.R. 10000").
  defp address?(text) do
    (text =~ @zip and not (text =~ @bill_number and id_key(text) != nil)) or
      text =~ @po_box or
      text =~ @directional or
      (text =~ @street_start and
         (String.contains?(text, ",") or text =~ @street_word))
  end
end
