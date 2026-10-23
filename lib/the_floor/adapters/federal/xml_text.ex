defmodule TheFloor.Adapters.Federal.XmlText do
  @moduledoc """
  Plain text extraction from bill XML with a streaming Saxy handler. The end of
  any element is a line break, whitespace within a line is collapsed and empty
  lines are dropped, so headings, enumerators and bodies land on their own lines.
  """
  @behaviour Saxy.Handler

  @uslm_namespace ~r/xmlns(?::\w+)?="http:\/\/(?:schemas\.gpo\.gov\/xml\/uslm|xml\.house\.gov\/schemas\/uslm\/[^"]*)"/

  @spec plain_text(binary()) :: {:ok, String.t()} | {:error, term()}
  def plain_text(xml) when is_binary(xml) do
    case Saxy.parse_string(xml, __MODULE__, {[], []}) do
      {:ok, {lines, current}} ->
        {:ok, [current | lines] |> Enum.reverse() |> finish_lines() |> Enum.join("\n")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns uslm when the document declares a USLM namespace, otherwise other."
  @spec schema(binary()) :: String.t()
  def schema(xml) when is_binary(xml) do
    if Regex.match?(@uslm_namespace, binary_part(xml, 0, min(byte_size(xml), 4096))),
      do: "uslm",
      else: "other"
  end

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}
  def handle_event(:end_document, _data, state), do: {:ok, state}
  def handle_event(:start_element, _element, state), do: {:ok, state}

  def handle_event(:end_element, _name, {lines, current}),
    do: {:ok, {[IO.iodata_to_binary(Enum.reverse(current)) | lines], []}}

  def handle_event(:characters, chars, {lines, current}), do: {:ok, {lines, [chars | current]}}
  def handle_event(:cdata, chars, state), do: handle_event(:characters, chars, state)

  defp finish_lines(lines) do
    lines
    |> Enum.map(fn
      parts when is_list(parts) -> parts |> Enum.reverse() |> IO.iodata_to_binary()
      line -> line
    end)
    |> Enum.map(&(&1 |> String.split() |> Enum.join(" ")))
    |> Enum.reject(&(&1 == ""))
  end
end
