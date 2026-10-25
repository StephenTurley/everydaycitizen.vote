defmodule EverydayCitizen.Search.Excerpt do
  @moduledoc """
  A short passage of a bill version around a search match, with the matched
  words marked and the section it sits in ("Sec. 4 Clocks"). It is taken from
  the first block of text that matches (for a phrase, the first holding the
  exact phrase, else the first holding all its words); a version without
  sections, or whose blocks never match, falls back to its whole text with no
  section label.

  Parts are plain text: the page escapes `:text` and renders `:mark` as a
  highlight, so markup in bill text never becomes HTML.
  """
  alias EverydayCitizen.Repo

  @type t :: %{section: String.t() | nil, parts: [{:text | :mark, String.t()}]}

  @start "<<<EC_MARK>>>"
  @stop "<<<EC_END>>>"
  @options "StartSel=#{@start}, StopSel=#{@stop}, MaxWords=30, MinWords=12, MaxFragments=1"
  @fallback_chars 200_000
  # every block's text, quoted blocks' included, once each, in document order
  @block_texts ~s|strict $.** ? (@.type() == "object" && exists(@.text)).text|

  # the search text ($2) as typed, and with its phrases loosened to all their words
  @exact "websearch_to_tsquery('english', $2)"
  @all_words "regexp_replace(websearch_to_tsquery('english', $2)::text, '<[0-9]+>|<->', '&', 'g')::tsquery"

  # ts_headline drops anything shaped like an HTML tag, so the text goes in with
  # &, < and > escaped and comes out unescaped, word for word
  defp escaped(sql),
    do: "replace(replace(replace(#{sql}, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')"

  defp unescape(text),
    do:
      text
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&amp;", "&")

  @doc "The excerpt of version `version_id` for the search text, or nil without text."
  @spec build(integer(), String.t()) :: t() | nil
  def build(version_id, text) do
    case matching_block(version_id, text) do
      {enum, heading, headline} -> excerpt(label(enum, heading), headline)
      nil -> whole_text(version_id, text)
    end
  end

  # every block's text, nested quoted blocks included, in order: the first
  # holding the exact query, else the first holding all its words, is
  # highlighted. Each block's tsvector is built once (OFFSET 0 keeps it so).
  defp matching_block(version_id, text) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT m.sec ->> 'enum', m.sec ->> 'heading',
          ts_headline('english', #{escaped("m.body")},
            CASE WHEN m.exact THEN #{@exact} ELSE #{@all_words} END, $3)
        FROM (
          SELECT s.sec, q.t #>> '{}' AS body, x.tsv @@ #{@exact} AS exact
          FROM bill_versions v
          CROSS JOIN LATERAL jsonb_array_elements(
            CASE WHEN jsonb_typeof(v.sections) = 'array' THEN v.sections ELSE '[]' END
          ) WITH ORDINALITY s(sec, ord)
          CROSS JOIN LATERAL jsonb_path_query(s.sec, '#{@block_texts}') WITH ORDINALITY q(t, n)
          CROSS JOIN LATERAL (
            SELECT to_tsvector('english', coalesce(q.t #>> '{}', '')) AS tsv OFFSET 0
          ) x
          WHERE v.id = $1 AND x.tsv @@ #{@all_words}
          ORDER BY exact DESC, s.ord, q.n
          LIMIT 1
        ) m
        """,
        [version_id, text, @options]
      )

    case rows do
      [[enum, heading, headline]] -> {enum, heading, headline}
      [] -> nil
    end
  end

  defp whole_text(version_id, text) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT ts_headline('english', #{escaped("left(plain_text, $3)")}, #{@all_words}, $4)
        FROM bill_versions WHERE id = $1 AND plain_text IS NOT NULL AND plain_text <> ''
        """,
        [version_id, text, @fallback_chars, @options]
      )

    case rows do
      [[headline]] -> excerpt(nil, headline)
      [] -> nil
    end
  end

  defp label(nil, _heading), do: nil

  defp label(enum, heading) do
    number = enum |> String.trim() |> String.trim_trailing(".")
    if heading in [nil, ""], do: "Sec. #{number}", else: "Sec. #{number} #{heading}"
  end

  defp excerpt(section, headline), do: %{section: section, parts: parts(headline)}

  defp parts(headline) do
    ~r/#{@start}(.*?)#{@stop}/s
    |> Regex.split(headline, include_captures: true, trim: true)
    |> Enum.map(fn
      @start <> rest -> {:mark, rest |> String.replace_suffix(@stop, "") |> unescape()}
      plain -> {:text, unescape(plain)}
    end)
  end
end
