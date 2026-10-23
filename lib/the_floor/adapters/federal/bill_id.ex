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
end
