defmodule EverydayCitizen.Search do
  @moduledoc """
  Finds bills from what someone typed: by number ("H.R. 22", "hr22", or a bare
  "22"), by name (any title the bill goes by), and by words in its latest text.

  Name matches rank in three tiers: the whole name, the name inside a longer
  title, then every word somewhere in a title. Within a tier, and for text
  matches, the bill that got further comes first (law, passed a chamber, had a
  roll-call vote, reported, introduced), then the newest.
  """
  import Ecto.Query

  alias EverydayCitizen.Legislation.Bill
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Search.Excerpt
  alias EverydayCitizen.Search.Query
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  @page_size 10
  @max_text_matches 1000

  @stages %{4 => :law, 3 => :passed, 2 => :voted, 1 => :reported, 0 => :introduced}

  # how far a bill (aliased b) got, as a number: higher is further
  @stage_rank """
  CASE
    WHEN EXISTS (SELECT 1 FROM bill_actions a WHERE a.bill_id = b.id
                 AND a.classification IN ('became_law', 'signed')) THEN 4
    WHEN EXISTS (SELECT 1 FROM bill_actions a WHERE a.bill_id = b.id
                 AND a.classification = 'passed_chamber') THEN 3
    WHEN EXISTS (SELECT 1 FROM votes v WHERE v.bill_id = b.id) THEN 2
    WHEN EXISTS (SELECT 1 FROM bill_actions a WHERE a.bill_id = b.id
                 AND a.classification = 'reported') THEN 1
    ELSE 0
  END
  """

  @type stage :: :law | :passed | :voted | :reported | :introduced

  # a bill number with only its letters and digits, lower-cased ("hr22")
  defmacrop identifier_key(identifier) do
    quote do
      fragment("lower(regexp_replace(?, '[^A-Za-z0-9]', '', 'g'))", unquote(identifier))
    end
  end

  @doc """
  The bill a number names, across all sessions. A bare number matches every
  kind of bill with that number, so it is always `{:many, _}` or `:none`.
  """
  @spec bill_by_number(Query.t()) :: {:one, Bill.t()} | {:many, [Bill.t()]} | :none
  def bill_by_number(%Query{id_key: id_key}) when is_binary(id_key) do
    case Repo.all(from b in newest_first(), where: identifier_key(b.identifier) == ^id_key) do
      [] -> :none
      [bill] -> {:one, bill}
      bills -> {:many, bills}
    end
  end

  def bill_by_number(%Query{number: number}) when is_binary(number) do
    pattern = "^[a-z]+0*#{String.to_integer(number)}$"

    case Repo.all(
           from b in newest_first(),
             where: fragment("? ~ ?", identifier_key(b.identifier), ^pattern)
         ) do
      [] -> :none
      bills -> {:many, bills}
    end
  end

  def bill_by_number(%Query{}), do: :none

  @doc """
  Bills whose titles match the query's name key, best first, each once with
  the title that matched and its cached AI summary text (never a new one).
  """
  @spec bills_by_name(Query.t(), pos_integer()) :: [
          %{bill: Bill.t(), title: String.t(), stage: stage(), summary: String.t() | nil}
        ]
  def bills_by_name(%Query{key: key}, limit) do
    case String.split(key || "") do
      [] -> []
      words -> name_matches(key, words, limit)
    end
  end

  defp name_matches(key, words, limit) do
    patterns = Enum.map(words, &"%#{escape_like(&1)}%")
    # the longest word narrows the trigram index; the rest filter what it finds
    longest = Enum.max_by(patterns, &String.length/1)

    %{rows: rows} =
      Repo.query!(
        """
        WITH candidates AS (
          SELECT t.bill_id, t.title FROM bill_titles t
          WHERE ec_name_key(t.title) LIKE $3 AND ec_name_key(t.title) LIKE ALL ($4)
          UNION ALL
          SELECT b.id, b.title FROM bills b
          WHERE ec_name_key(b.title) LIKE $3 AND ec_name_key(b.title) LIKE ALL ($4)
        ), tiered AS (
          SELECT DISTINCT ON (bill_id) bill_id, title,
            CASE WHEN ec_name_key(title) = $1 THEN 1
                 WHEN ec_name_key(title) LIKE $2 THEN 2
                 ELSE 3 END AS tier
          FROM candidates
          ORDER BY bill_id, tier, length(title), title
        )
        SELECT t.bill_id, t.title, #{@stage_rank} AS stage
        FROM tiered t JOIN bills b ON b.id = t.bill_id
        ORDER BY t.tier, stage DESC, b.introduced_on DESC NULLS LAST, b.id DESC
        LIMIT $5
        """,
        [key, "%#{escape_like(key)}%", longest, patterns, limit]
      )

    bills = bills_by_id(Enum.map(rows, &hd/1))

    for [id, title, stage] <- rows do
      bill = Map.fetch!(bills, id)

      %{
        bill: bill,
        title: title,
        stage: Map.fetch!(@stages, stage),
        summary: cached_summary(bill)
      }
    end
  end

  @doc """
  Bills whose latest text matches the query's words, leaving out
  `exclude_bill_ids` (those already found by name), ten to a page with an
  excerpt each. `total` counts at most 1,000 matches.
  """
  @spec bills_by_text(Query.t(), [integer()], pos_integer()) :: %{
          results: [%{bill: Bill.t(), excerpt: Excerpt.t() | nil, stage: stage()}],
          total: non_neg_integer(),
          more?: boolean()
        }
  def bills_by_text(%Query{text: text}, exclude_bill_ids, page) do
    if empty_tsquery?(text),
      do: %{results: [], total: 0, more?: false},
      else: text_matches(text, exclude_bill_ids, page)
  end

  # the latest version of each matching bill, at most 1,000 of them
  @text_hits """
  SELECT hit.bill_id, hit.id FROM bill_versions hit
  WHERE hit.plain_text IS NOT NULL
    AND to_tsvector('english', hit.plain_text) @@ websearch_to_tsquery('english', $1)
    AND NOT (hit.bill_id = ANY ($2))
    AND hit.id = (
      SELECT l.id FROM bill_versions l
      WHERE l.bill_id = hit.bill_id AND l.plain_text IS NOT NULL AND l.plain_text <> ''
      ORDER BY l.date DESC NULLS LAST, l.id DESC
      LIMIT 1)
  LIMIT $3
  """

  defp text_matches(text, exclude_bill_ids, page) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT h.bill_id, h.id, #{@stage_rank} AS stage, count(*) OVER () AS total
        FROM (#{@text_hits}) h JOIN bills b ON b.id = h.bill_id
        ORDER BY stage DESC, b.introduced_on DESC NULLS LAST, b.id DESC
        LIMIT $4 OFFSET $5
        """,
        [text, exclude_bill_ids, @max_text_matches, @page_size, (page - 1) * @page_size]
      )

    total =
      case rows do
        [[_, _, _, total] | _] -> total
        [] when page == 1 -> 0
        # a page past the end has no rows to carry the count
        [] -> count_text_matches(text, exclude_bill_ids)
      end

    bills = bills_by_id(Enum.map(rows, &hd/1))

    results =
      for [bill_id, version_id, stage, _] <- rows do
        %{
          bill: Map.fetch!(bills, bill_id),
          excerpt: Excerpt.build(version_id, text),
          stage: Map.fetch!(@stages, stage)
        }
      end

    %{results: results, total: total, more?: page * @page_size < total}
  end

  defp count_text_matches(text, exclude_bill_ids) do
    %{rows: [[total]]} =
      Repo.query!("SELECT count(*) FROM (#{@text_hits}) h", [
        text,
        exclude_bill_ids,
        @max_text_matches
      ])

    total
  end

  defp empty_tsquery?(text) do
    %{rows: [[nodes]]} =
      Repo.query!("SELECT numnode(websearch_to_tsquery('english', $1))", [text])

    nodes == 0
  end

  # the summary the bill page shows above the text, if one is cached
  defp cached_summary(bill) do
    with {subject, input} <- Inputs.bill(bill),
         %{summary: summary} <- Summaries.get_ai(:bill, subject, input) do
      summary
    else
      _ -> nil
    end
  end

  defp bills_by_id([]), do: %{}

  defp bills_by_id(ids),
    do: Repo.all(from b in Bill, where: b.id in ^ids) |> Map.new(&{&1.id, &1})

  defp newest_first,
    do:
      from(b in Bill, order_by: [desc_nulls_last: b.introduced_on, asc: b.identifier, asc: b.id])

  defp escape_like(word), do: String.replace(word, ["\\", "%", "_"], &"\\#{&1}")
end
