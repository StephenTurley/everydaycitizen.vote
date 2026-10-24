defmodule TheFloor.Adapters.Federal.BillSections do
  @moduledoc """
  Splits bill XML (the bill DTD or USLM) into its sections, for the bill page and
  for attaching section summaries later. Returns, in document order:

    * `%{"kind" => "title", "enum", "heading"}` for each division, title, part or
      chapter, before its sections;
    * `%{"kind" => "section", "enum", "heading", "blocks"}`, where `blocks` flattens
      the section's own text and its subsections, paragraphs and deeper levels into
      `%{"level", "enum", "heading", "text"}` (level 0 for the section's own text and
      subsections, 1 paragraph, 2 subparagraph, 3 clause, 4 subclause, 5 item).

  Text inside `<quoted-block>` (language inserted into existing law) stays inline
  in the block that quotes it; its sections are not the bill's sections.
  """

  @containers ~w(division subdivision title subtitle part subpart chapter subchapter)
  @levels %{
    "subsection" => 0,
    "paragraph" => 1,
    "subparagraph" => 2,
    "clause" => 3,
    "subclause" => 4,
    "item" => 5,
    "subitem" => 5
  }
  @enum ~w(enum num)
  @heading ~w(header heading)

  @type entry :: %{String.t() => term()}

  @spec parse(binary()) :: {:ok, [entry()]} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    case Saxy.SimpleForm.parse_string(xml) do
      {:ok, root} -> {:ok, root |> walk([]) |> Enum.reverse()}
      {:error, _} = error -> error
    end
  end

  @doc "The sections of `xml`, or `[]` when it cannot be parsed (so it is not retried)."
  @spec sections_or_empty(binary()) :: [entry()]
  def sections_or_empty(xml) do
    case parse(xml) do
      {:ok, sections} -> sections
      {:error, _} -> []
    end
  end

  defp walk({name, _attrs, children} = el, acc) do
    case local(name) do
      "section" -> [section(el) | acc]
      "quoted-block" -> acc
      # a real division/title has a number or heading (metadata `<dc:title>` has neither)
      n when n in @containers -> Enum.reduce(children, container(el, acc), &walk/2)
      _ -> Enum.reduce(children, acc, &walk/2)
    end
  end

  defp walk(_text, acc), do: acc

  defp container(el, acc) do
    case {label(el, @enum), label(el, @heading)} do
      {nil, nil} -> acc
      {enum, heading} -> [%{"kind" => "title", "enum" => enum, "heading" => heading} | acc]
    end
  end

  defp section(el) do
    own =
      case own_text(el) do
        "" -> []
        text -> [%{"level" => 0, "enum" => nil, "heading" => nil, "text" => text}]
      end

    %{
      "kind" => "section",
      "enum" => label(el, @enum),
      "heading" => label(el, @heading),
      "blocks" => own ++ Enum.flat_map(structural(el), &block/1)
    }
  end

  defp block({name, _attrs, _children} = el) do
    [
      %{
        "level" => Map.fetch!(@levels, local(name)),
        "enum" => label(el, @enum),
        "heading" => label(el, @heading),
        "text" => own_text(el)
      }
      | Enum.flat_map(structural(el), &block/1)
    ]
  end

  defp structural({_name, _attrs, children}),
    do: for({n, _, _} = c <- children, Map.has_key?(@levels, local(n)), do: c)

  # The element's text outside its labels and its nested levels.
  defp own_text({_name, _attrs, children}) do
    children
    |> Enum.reject(fn
      {n, _, _} -> local(n) in @enum or local(n) in @heading or Map.has_key?(@levels, local(n))
      _text -> false
    end)
    |> Enum.map_join(" ", &text_of/1)
    |> collapse()
  end

  defp label({_name, _attrs, children}, names) do
    Enum.find_value(children, fn
      {n, _, _} = c -> if local(n) in names, do: blank_to_nil(collapse(text_of(c)))
      _text -> nil
    end)
  end

  defp text_of(text) when is_binary(text), do: text
  defp text_of({_name, _attrs, children}), do: Enum.map_join(children, "", &text_of/1)
  defp text_of(_other), do: ""

  defp local(name), do: name |> String.split(":") |> List.last()

  defp collapse(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text
end
