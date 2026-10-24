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

  Language quoted into existing law (`<quoted-block>`, USLM `<quotedContent>`)
  stays inside the section that quotes it, as `%{"level", "quote"}`: `level` is
  that of the element holding the quote, and `quote` lists the quoted text's own
  blocks with levels counted from 0 inside it (a quoted section or subsection is
  0, a paragraph 1, and so on; a quoted title or part is a heading-only block at
  0). Quotes can nest. Words after a quote (`<after-quoted-block>`, e.g. "; and")
  follow it as a plain block at its level; a lone closing period is dropped.

  `format/0` numbers this output shape, so text split by an older one is redone.
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
  @quote_levels Map.put(@levels, "section", 0)
  @quotes ~w(quoted-block quotedContent)
  @after_quote "after-quoted-block"
  @enum ~w(enum num)
  @heading ~w(header heading)
  @not_own_text @enum ++
                  @heading ++ @quotes ++ @containers ++ [@after_quote | Map.keys(@quote_levels)]

  @doc "The version of this module's output shape."
  @spec format() :: pos_integer()
  def format, do: 2

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
      n when n in @quotes -> acc
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
    %{
      "kind" => "section",
      "enum" => label(el, @enum),
      "heading" => label(el, @heading),
      "blocks" => own_block(el) ++ child_blocks(el, 0, @levels)
    }
  end

  defp own_block(el) do
    case own_text(el) do
      "" -> []
      text -> [%{"level" => 0, "enum" => nil, "heading" => nil, "text" => text}]
    end
  end

  defp block({name, _attrs, _children} = el, levels) do
    level = Map.fetch!(levels, local(name))

    [
      %{
        "level" => level,
        "enum" => label(el, @enum),
        "heading" => label(el, @heading),
        "text" => own_text(el)
      }
      | child_blocks(el, level, levels)
    ]
  end

  # The element's nested levels and quotes, in document order.
  defp child_blocks({_name, _attrs, children}, level, levels) do
    Enum.flat_map(children, fn
      {name, _, _} = child ->
        n = local(name)

        cond do
          Map.has_key?(levels, n) ->
            block(child, levels)

          n in @quotes ->
            [%{"level" => level, "quote" => quote_blocks(child)} | after_quote(child, level)]

          n in @containers ->
            heading_block(child) ++ child_blocks(child, 0, levels)

          true ->
            []
        end

      _text ->
        []
    end)
  end

  defp quote_blocks(el), do: own_block(el) ++ child_blocks(el, 0, @quote_levels)

  defp heading_block(el) do
    case {label(el, @enum), label(el, @heading)} do
      {nil, nil} -> []
      {enum, heading} -> [%{"level" => 0, "enum" => enum, "heading" => heading, "text" => ""}]
    end
  end

  defp after_quote({_name, _attrs, children}, level) do
    for {n, _, _} = c <- children,
        local(n) == @after_quote,
        text = collapse(text_of(c)),
        not (text =~ ~r/^[\p{P}\s]*$/u),
        do: %{"level" => level, "enum" => nil, "heading" => nil, "text" => text}
  end

  # The element's text outside its labels and its nested levels.
  defp own_text({_name, _attrs, children}) do
    children
    |> Enum.reject(fn
      {n, _, _} -> local(n) in @not_own_text
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
