defmodule EverydayCitizen.Search do
  @moduledoc """
  Finds bills from what someone typed: by number ("H.R. 22", "hr22", or a bare
  "22"), by name (any title the bill goes by), and by words in its latest text.

  Name matches rank in three tiers: the whole name, the name inside a longer
  title, then every word somewhere in a title. Within a tier, and for text
  matches, the bill that got further comes first (law, passed a chamber, had a
  roll-call vote, reported, introduced), then the newest.

  Text search treats a phrase as all of its words (a deliberate loosening:
  checking word order would rebuild multi-MB texts' tsvectors per query).
  """
  import Ecto.Query

  alias EverydayCitizen.Legislation.Bill
  alias EverydayCitizen.Legislature.{Body, Membership, Person}
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Reps
  alias EverydayCitizen.Search.Excerpt
  alias EverydayCitizen.Search.Query
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  @page_size 10
  @max_text_matches 1000
  @text_timeout_ms 3000

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
  The place the query names, if any, with its current members; and the people
  whose names match, current members first within each tier of match (the whole
  name, the name inside a longer one, then a small typo), then by name. Each
  person carries their latest chamber membership. People listed under the place
  are left out of `people`.
  """
  @spec people(Query.t(), pos_integer()) :: %{
          place: nil | %{name: String.t(), reps: [Reps.rep()]},
          people: [%{person: Person.t(), membership: Membership.t() | nil, body: Body.t() | nil}]
        }
  def people(%Query{text: text, key: key}, limit) do
    place = Reps.place(text)
    skip = if place, do: Enum.map(place.reps, & &1.person.id), else: []
    %{place: place, people: people_by_name(key, skip, limit)}
  end

  defp people_by_name(key, _skip, _limit) when key in [nil, ""], do: []

  defp people_by_name(key, skip, limit) do
    today = Date.utc_today()
    like = "%#{escape_like(key)}%"

    %{rows: rows} =
      Repo.query!(
        """
        SELECT id FROM (
          SELECT p.id, p.name,
            CASE WHEN ec_name_key(p.name) = $1 THEN 1
                 WHEN ec_name_key(p.name) LIKE $2 THEN 2
                 ELSE 3 END AS tier,
            EXISTS (SELECT 1 FROM memberships m JOIN bodies cb ON cb.id = m.body_id
                    WHERE m.person_id = p.id AND cb.classification = 'chamber'
                    AND (m.start_date IS NULL OR m.start_date <= $3)
                    AND (m.end_date IS NULL OR m.end_date >= $3)) AS current
          FROM people p
          WHERE NOT (p.id = ANY ($4))
            AND (ec_name_key(p.name) LIKE $2
                 OR word_similarity($1, ec_name_key(p.name)) >= 0.5)
        ) found
        ORDER BY tier, NOT current, name, id
        LIMIT $5
        """,
        [key, like, today, skip, limit]
      )

    ids = Enum.map(rows, &hd/1)
    people = Repo.all(from p in Person, where: p.id in ^ids) |> Map.new(&{&1.id, &1})
    chambers = latest_chamber_memberships(ids)

    for id <- ids do
      {membership, body} = Map.get(chambers, id, {nil, nil})
      %{person: Map.fetch!(people, id), membership: membership, body: body}
    end
  end

  defp latest_chamber_memberships(ids) do
    from(m in Membership,
      join: b in Body,
      on: b.id == m.body_id,
      where: m.person_id in ^ids and b.classification == "chamber",
      order_by: [desc_nulls_last: m.start_date, desc: m.id],
      select: {m.person_id, m, b}
    )
    |> Repo.all()
    |> Enum.uniq_by(&elem(&1, 0))
    |> Map.new(fn {id, m, b} -> {id, {m, b}} end)
  end

  @doc """
  Bills whose latest text matches the query's words, leaving out
  `exclude_bill_ids` (those already found by name), ten to a page with an
  excerpt each. `total` counts at most 1,000 matches (`opts[:cap]`), and
  those kept are the furthest along. A quoted or hyphenated phrase matches
  bills containing all its words, in any order; the excerpt marks the exact
  phrase where it occurs. A search running past 3 seconds (`opts[:timeout_ms]`)
  finds nothing.
  """
  @spec bills_by_text(Query.t(), [integer()], pos_integer(), keyword()) :: %{
          results: [%{bill: Bill.t(), excerpt: Excerpt.t() | nil, stage: stage()}],
          total: non_neg_integer(),
          more?: boolean()
        }
  def bills_by_text(%Query{text: text}, exclude_bill_ids, page, opts \\ []) do
    cap = Keyword.get(opts, :cap, @max_text_matches)
    timeout_ms = Keyword.get(opts, :timeout_ms, @text_timeout_ms)

    with false <- empty_tsquery?(text),
         {:ok, rows, total} <- text_hits(text, exclude_bill_ids, page, cap, timeout_ms) do
      bills = bills_by_id(Enum.map(rows, &hd/1))

      results =
        for [bill_id, version_id, stage] <- rows do
          %{
            bill: Map.fetch!(bills, bill_id),
            excerpt: Excerpt.build(version_id, text),
            stage: Map.fetch!(@stages, stage)
          }
        end

      %{results: results, total: total, more?: page * @page_size < total}
    else
      _ -> %{results: [], total: 0, more?: false}
    end
  end

  # The query's words with phrase operators made AND: a phrase check would
  # rebuild the tsvector of every candidate's full text, which takes seconds on
  # multi-MB bills.
  @text_query "regexp_replace(websearch_to_tsquery('english', $1)::text, '<[0-9]+>|<->', '&', 'g')::tsquery"

  # The latest version of each matching bill, furthest along first, capped.
  @text_hits """
  SELECT hit.bill_id, hit.id, #{@stage_rank} AS stage, b.introduced_on
  FROM bill_versions hit JOIN bills b ON b.id = hit.bill_id
  WHERE hit.plain_text IS NOT NULL
    AND to_tsvector('english', hit.plain_text) @@ #{@text_query}
    AND NOT (hit.bill_id = ANY ($2))
    AND hit.id = (
      SELECT l.id FROM bill_versions l
      WHERE l.bill_id = hit.bill_id AND l.plain_text IS NOT NULL AND l.plain_text <> ''
      ORDER BY l.date DESC NULLS LAST, l.id DESC
      LIMIT 1)
  ORDER BY stage DESC, b.introduced_on DESC NULLS LAST, b.id DESC
  LIMIT $3
  """

  # runs under a statement timeout; a search that takes too long finds nothing
  defp text_hits(text, exclude_bill_ids, page, cap, timeout_ms) do
    {:ok, {rows, total}} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL statement_timeout = #{Integer.to_string(timeout_ms)}")

        %{rows: rows} =
          Repo.query!(
            """
            SELECT h.bill_id, h.id, h.stage, count(*) OVER () AS total
            FROM (#{@text_hits}) h
            ORDER BY h.stage DESC, h.introduced_on DESC NULLS LAST, h.bill_id DESC
            LIMIT $4 OFFSET $5
            """,
            [text, exclude_bill_ids, cap, @page_size, (page - 1) * @page_size]
          )

        total =
          case rows do
            [[_, _, _, total] | _] -> total
            [] when page == 1 -> 0
            # a page past the end has no rows to carry the count
            [] -> count_text_hits(text, exclude_bill_ids, cap)
          end

        {Enum.map(rows, &Enum.take(&1, 3)), total}
      end)

    {:ok, rows, total}
  rescue
    e in Postgrex.Error ->
      if e.postgres[:code] == :query_canceled, do: :timeout, else: reraise(e, __STACKTRACE__)
  end

  defp count_text_hits(text, exclude_bill_ids, cap) do
    %{rows: [[total]]} =
      Repo.query!("SELECT count(*) FROM (#{@text_hits}) h", [text, exclude_bill_ids, cap])

    total
  end

  @doc """
  Whether the query has any words text search can use: one made only of
  common words ("the of") or punctuation has none, so text search finds
  nothing whatever the bills say. Nor does one made only of excluded words
  ("-tax"): it matches nearly every bill and no index can narrow it, so it
  would read every text.
  """
  @spec text_searchable?(Query.t()) :: boolean()
  def text_searchable?(%Query{text: text}), do: not empty_tsquery?(text)

  # querytree is '' for no words and 'T' when nothing the index can use is left
  defp empty_tsquery?(text) do
    %{rows: [[tree]]} = Repo.query!("SELECT querytree(#{@text_query})", [text])
    tree in ["", "T"]
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
