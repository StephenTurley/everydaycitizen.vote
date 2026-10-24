defmodule TheFloor.Ingest.SafeHtml do
  @moduledoc """
  Reduces source HTML (official summaries) to a small allow-list before it is
  stored and rendered: paragraphs, lists, emphasis and line breaks, with no
  attributes. Other elements give way to their text; script and style elements
  are dropped with their content. Text is escaped.
  """

  @allowed ~w(p ul ol li strong em b i br)
  @dropped ~w(script style)

  @spec sanitize(String.t()) :: String.t()
  def sanitize(html) when is_binary(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Enum.map_join(&render/1)
  end

  defp render(text) when is_binary(text), do: escape(text)
  defp render({:comment, _}), do: ""
  defp render({tag, _attrs, _children}) when tag in @dropped, do: ""
  defp render({"br", _attrs, _children}), do: "<br>"

  defp render({tag, _attrs, children}) when tag in @allowed,
    do: "<#{tag}>" <> Enum.map_join(children, &render/1) <> "</#{tag}>"

  defp render({_tag, _attrs, children}), do: Enum.map_join(children, &render/1)
  defp render(_other), do: ""

  defp escape(text), do: text |> Plug.HTML.html_escape_to_iodata() |> IO.iodata_to_binary()
end
