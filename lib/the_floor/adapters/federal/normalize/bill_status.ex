defmodule TheFloor.Adapters.Federal.Normalize.BillStatus do
  @moduledoc """
  Converts a GovInfo BILLSTATUS bulk XML file into the maps the Congress.gov
  API returns for the same bill, so `Normalize.Bill` handles both sources. The
  bulk schema uses the API's field names: an element whose children are all
  `<item>` becomes a list, an element with only text becomes a string, an empty
  element becomes nil, and any other element becomes a map.
  """

  @type parts :: %{
          detail: map(),
          subjects: map(),
          actions: [map()],
          cosponsors: [map()],
          text: map()
        }

  @spec parse(binary()) :: {:ok, parts()} | {:error, term()}
  def parse(xml) do
    with {:ok, {"billStatus", _, children}} <- Saxy.SimpleForm.parse_string(xml),
         {"bill", _, _} = node <- List.keyfind(children, "bill", 0) || {:error, :no_bill} do
      bill = node |> value() |> Map.update("textVersions", nil, &text_versions/1)

      {:ok,
       %{
         detail: %{"bill" => bill},
         subjects: %{"subjects" => bill["subjects"]},
         actions: bill["actions"] || [],
         cosponsors: bill["cosponsors"] || [],
         text: %{"textVersions" => bill["textVersions"] || []}
       }}
    else
      {:ok, {other, _, _}} -> {:error, {:unexpected_root, other}}
      {:error, _} = error -> error
    end
  end

  defp value({_name, _attrs, children}) do
    case Enum.filter(children, &is_tuple/1) do
      [] ->
        case children |> Enum.join() |> String.trim() do
          "" -> nil
          text -> text
        end

      elements ->
        if Enum.all?(elements, &match?({"item", _, _}, &1)),
          do: Enum.map(elements, &value/1),
          else: Map.new(elements, fn {name, _, _} = el -> {name, value(el)} end)
    end
  end

  # Bulk formats carry only a url; the API also labels each with a type, which
  # `Normalize.Bill.versions/3` keys on.
  defp text_versions(nil), do: nil

  defp text_versions(versions) do
    Enum.map(versions, fn v ->
      Map.update(v, "formats", [], fn formats ->
        Enum.map(formats || [], &Map.put(&1, "type", format_type(&1["url"])))
      end)
    end)
  end

  defp format_type(url) when is_binary(url) do
    case url |> Path.extname() |> String.downcase() do
      ".xml" -> "Formatted XML"
      ".htm" -> "Formatted Text"
      ".pdf" -> "PDF"
      _ -> nil
    end
  end

  defp format_type(_), do: nil
end
