defmodule TheFloor.Adapters.Federal.BillId do
  @moduledoc """
  The single place that builds and parses federal bill external ids, display
  identifiers and classifications. Other federal code must not rebuild these.
  """

  @types %{
    "HR" => {"H.R.", "bill"},
    "S" => {"S.", "bill"},
    "HRES" => {"H.Res.", "resolution"},
    "SRES" => {"S.Res.", "resolution"},
    "HJRES" => {"H.J.Res.", "joint_resolution"},
    "SJRES" => {"S.J.Res.", "joint_resolution"},
    "HCONRES" => {"H.Con.Res.", "concurrent_resolution"},
    "SCONRES" => {"S.Con.Res.", "concurrent_resolution"}
  }

  @slugs %{
    "hr" => "house-bill",
    "s" => "senate-bill",
    "hres" => "house-resolution",
    "sres" => "senate-resolution",
    "hjres" => "house-joint-resolution",
    "sjres" => "senate-joint-resolution",
    "hconres" => "house-concurrent-resolution",
    "sconres" => "senate-concurrent-resolution"
  }

  @doc "The bill's page for people on Congress.gov, from its external id (`nil` if not one)."
  @spec web_url(String.t()) :: String.t() | nil
  def web_url(external_id) do
    with [congress, type, number] <- String.split(external_id, "-"),
         {n, ""} <- Integer.parse(congress),
         {:ok, slug} <- Map.fetch(@slugs, type) do
      "https://www.congress.gov/bill/#{ordinal(n)}-congress/#{slug}/#{number}"
    else
      _ -> nil
    end
  end

  defp ordinal(n) when rem(n, 100) in 11..13, do: "#{n}th"
  defp ordinal(n) when rem(n, 10) == 1, do: "#{n}st"
  defp ordinal(n) when rem(n, 10) == 2, do: "#{n}nd"
  defp ordinal(n) when rem(n, 10) == 3, do: "#{n}rd"
  defp ordinal(n), do: "#{n}th"

  @spec external_id(integer(), String.t(), integer() | String.t()) :: String.t()
  def external_id(congress, type_code, number) do
    "#{congress}-#{String.downcase(type_code)}-#{number}"
  end

  @spec identifier(String.t(), integer() | String.t()) :: String.t()
  def identifier(type_code, number) do
    {display, _} = Map.fetch!(@types, String.upcase(type_code))
    "#{display} #{number}"
  end

  @spec classification(String.t()) :: String.t()
  def classification(type_code) do
    {_, classification} = Map.fetch!(@types, String.upcase(type_code))
    classification
  end

  @doc """
  Parses a display label such as `"H.R. 1234"`, `"S.J.Res.12"` or `"H. Con. Res. 3"`
  into an external id; nil for anything that is not a bill label (e.g. `"PN 123"`).
  """
  @spec from_label(String.t() | nil, integer()) :: String.t() | nil
  def from_label(label, congress) when is_binary(label) do
    with [_, type, number] <- Regex.run(~r/^\s*([A-Za-z][A-Za-z.\s]*?)\s*(\d+)\s*$/, label),
         code = type |> String.replace(~r/[.\s]/, "") |> String.upcase(),
         true <- Map.has_key?(@types, code) do
      external_id(congress, code, number)
    else
      _ -> nil
    end
  end

  def from_label(_label, _congress), do: nil

  @scan ~r/(?<![\w.])(H\.\s?Con\.\s?Res|S\.\s?Con\.\s?Res|H\.\s?J\.\s?Res|S\.\s?J\.\s?Res|H\.\s?Res|S\.\s?Res|H\.\s?R|S)\.?\s?(\d+)/

  @doc """
  Finds bill labels (`"H.R. 1234"`, `"S.J.Res. 12"`, ...) anywhere in free text and
  returns their external ids in order of first appearance, without duplicates.
  """
  @spec scan(String.t() | nil, integer()) :: [String.t()]
  def scan(text, congress) when is_binary(text) do
    @scan
    |> Regex.scan(text, capture: :all_but_first)
    |> Enum.map(fn [type, number] ->
      code = type |> String.replace(~r/[.\s]/, "") |> String.upcase()
      external_id(congress, code, number)
    end)
    |> Enum.uniq()
  end

  def scan(_text, _congress), do: []
end
