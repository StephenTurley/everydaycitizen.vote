defmodule EverydayCitizen.BillHistory do
  @moduledoc """
  Where each part of a bill's text came from ("blame" for a bill), computed from
  the stored sections of its versions, oldest first.

  A section is followed across versions by its key: its heading (letters only,
  lowercased), else its number, with the occurrence counted when a version has
  several with the same key. Its text is its paragraphs; whitespace-only
  differences are not changes. For the sections of one version:

    * `:original` — in the first version with sections and never changed;
    * `:changed` — in the first version, changed in the versions in `changed_in`;
    * `:added` — first appears in the later version `added_in` (and may have
      changed after, in `changed_in`).
  """
  import Ecto.Query

  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Legislation.{BillAction, BillVersion}
  alias EverydayCitizen.Legislature.Membership
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Votes.{Vote, VotePosition}

  # dates of record are kept in the legislature's local time
  @zone "America/New_York"

  @type origin :: %{
          status: :original | :changed | :added,
          added_in: String.t(),
          changed_in: [String.t()]
        }
  @type op :: {:eq | :del | :ins, String.t()}

  @doc "The bill's versions, oldest first (undated last)."
  @spec versions(map()) :: [
          %{code: String.t(), classification: String.t() | nil, date: Date.t() | nil}
        ]
  def versions(bill), do: bill |> version_list() |> Enum.map(&Map.delete(&1, :sections))

  @doc "The bill's versions with their sections, to pass to the functions below so one request loads them once."
  @spec load(map()) :: [map()]
  def load(bill), do: rows(bill)

  @doc "Where each section of version `code` came from, by its index; `%{}` with fewer than two versions to compare."
  @spec origins(map(), String.t(), [map()] | nil) :: %{non_neg_integer() => origin()}
  def origins(bill, code, loaded \\ nil) do
    case lineage(loaded || rows(bill), code) do
      {[_, _ | _] = keyed, target} ->
        target |> Enum.with_index() |> Map.new(fn {{key, _}, i} -> {i, origin(keyed, key)} end)

      _ ->
        %{}
    end
  end

  @doc """
  The subjects of a version's summary (each naming the section numbers it comes
  from) whose sections were all added after the bill's first version, each with
  the version that added it (its first section's). A subject naming a section
  the version doesn't have, or one whose number two sections share, or none, is
  left out. `sections` are the version's
  stored sections and `origins` theirs, from `origins/3`.
  """
  @spec added_subjects([%{name: String.t(), sections: [String.t()]}], [map()], %{
          non_neg_integer() => origin()
        }) :: [%{name: String.t(), added_in: String.t()}]
  def added_subjects(subjects, sections, origins) do
    # a number two sections share names neither
    index =
      sections
      |> Enum.with_index()
      |> Enum.group_by(fn {s, _} -> number(s["enum"]) end, fn {_, i} -> i end)
      |> Map.new(fn {n, is} -> {n, match?([_], is) && hd(is)} end)

    for %{name: name, sections: [_ | _] = numbers} <- subjects,
        found = Enum.map(numbers, &(is_integer(index[&1]) && origins[index[&1]])),
        Enum.all?(found, &match?(%{status: :added}, &1)),
        do: %{name: name, added_in: hd(found).added_in}
  end

  # "3." and "SEC. 3" both number section "3"
  defp number(nil), do: nil

  defp number(enum),
    do:
      enum
      |> to_string()
      |> String.replace(~r/[^0-9A-Za-z]/, "")
      |> String.replace_prefix("SEC", "")

  @doc """
  Section `index` of version `code` against its wording before its most recent
  change: `%{from, to, paragraphs}`, each paragraph a list of `{:eq | :del | :ins,
  text}`. nil for a section never changed (or added and never changed since).
  """
  @spec comparison(map(), String.t(), non_neg_integer(), [map()] | nil) ::
          %{from: String.t(), to: String.t(), paragraphs: [[op()]]} | nil
  def comparison(bill, code, index, loaded \\ nil) do
    with {[_, _ | _] = keyed, target} <- lineage(loaded || rows(bill), code),
         {key, paragraphs} <- Enum.at(target, index),
         %{changed_in: [_ | _] = changed} <- origin(keyed, key),
         to = List.last(changed),
         {from, before} <- before_change(keyed, key, to) do
      %{from: from, to: to, paragraphs: diff(before, paragraphs)}
    else
      _ -> nil
    end
  end

  @doc """
  What happened between each version and the one before it, oldest first: the
  version, the window `(from_date, date]` and, inside it, the bill's actions,
  committee steps, amendments (by latest action), roll calls on the bill, and
  roll calls on its procedural measures (such as the rule it was taken up
  under) as `%{ref, vote}`.
  """
  @spec steps(map()) :: [map()]
  def steps(bill) do
    versions = versions(bill)

    actions =
      Repo.all(from a in BillAction, where: a.bill_id == ^bill.id, order_by: [a.date, a.position])

    committees = Legislation.committee_activities(bill.id)
    amendments = Legislation.amendments(bill.id)
    votes = bill_votes(bill)
    related = related_votes(bill)

    versions
    |> Enum.with_index()
    |> Enum.map(fn {version, i} ->
      from = if i > 0, do: Enum.at(versions, i - 1).date
      inside = &in_window?(&1, from, version.date)

      Map.merge(version, %{
        from_date: from,
        actions: Enum.filter(actions, &inside.(&1.date)),
        committees: Enum.filter(committees, &inside.(&1.date)),
        amendments: Enum.filter(amendments, &(&1.agreed and inside.(&1.latest_action_date))),
        votes: Enum.filter(votes, &inside.(local_date(&1.voted_at))),
        related_votes: Enum.filter(related, &inside.(local_date(&1.vote.voted_at)))
      })
    end)
  end

  @doc """
  Each person's part in a step: their positions on its roll calls (procedural
  ones first, by date) as `{vote, option}`, and the step's committees they are
  members of. People in the order given; nothing found gives empty lists.
  """
  @spec involvement(map(), [map()]) :: [
          %{person: map(), votes: [{Vote.t(), String.t()}], committees: [map()]}
        ]
  def involvement(step, people) do
    person_ids = Enum.map(people, & &1.id)

    votes =
      (Enum.map(step.related_votes, & &1.vote) ++ step.votes)
      |> Enum.sort_by(& &1.voted_at, DateTime)

    positions =
      from(p in VotePosition,
        where: p.vote_id in ^Enum.map(votes, & &1.id) and p.person_id in ^person_ids,
        select: {{p.person_id, p.vote_id}, p.option}
      )
      |> Repo.all()
      |> Map.new()

    # a referral isn't the committee acting on the text; a markup or report is
    bodies =
      for a <- step.committees, a.body, a.kind in ["markup", "reported"], uniq: true, do: a.body

    member_of =
      from(m in Membership,
        where: m.person_id in ^person_ids and m.body_id in ^Enum.map(bodies, & &1.id),
        select: {m.person_id, m.body_id}
      )
      |> Repo.all()
      |> MapSet.new()

    for person <- people do
      %{
        person: person,
        votes: for(v <- votes, option = positions[{person.id, v.id}], do: {v, option}),
        committees: Enum.filter(bodies, &MapSet.member?(member_of, {person.id, &1.id}))
      }
    end
  end

  defp bill_votes(bill) do
    from(v in Vote, where: v.bill_id == ^bill.id, order_by: [v.voted_at, v.id], preload: :body)
    |> Repo.all()
  end

  # votes on the bill's procedural measures, stored as bills or only by reference
  defp related_votes(bill) do
    case Legislation.related_refs(bill.id, "procedural") do
      [] ->
        []

      refs ->
        from(v in Vote,
          left_join: b in assoc(v, :bill),
          where: b.external_id in ^refs or v.bill_ref in ^refs,
          order_by: [v.voted_at, v.id],
          preload: [:body, :bill]
        )
        |> Repo.all()
        |> Enum.map(&%{ref: (&1.bill && &1.bill.external_id) || &1.bill_ref, vote: &1})
    end
  end

  defp in_window?(nil, _from, _to), do: false

  defp in_window?(date, from, to),
    do: (is_nil(from) or Date.after?(date, from)) and (is_nil(to) or not Date.after?(date, to))

  defp local_date(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.shift_zone!(@zone) |> DateTime.to_date()

  defp local_date(%DateTime{} = at), do: at |> DateTime.shift_zone!(@zone) |> DateTime.to_date()

  @doc """
  The texts an explanation of section `index`'s change in version `code` is
  written from: `{:added, paragraphs}` for a section added after the first
  version, `{:changed, before, after}` for one changed since, else nil.
  """
  @spec change_texts(map(), String.t(), non_neg_integer(), [map()] | nil) ::
          {:added, [String.t()]} | {:changed, [String.t()], [String.t()]} | nil
  def change_texts(bill, code, index, loaded \\ nil) do
    with {[_, _ | _] = keyed, target} <- lineage(loaded || rows(bill), code),
         {key, paragraphs} <- Enum.at(target, index) do
      case origin(keyed, key) do
        %{status: :added} ->
          {:added, paragraphs}

        %{changed_in: [_ | _] = changed} ->
          {_from, before} = before_change(keyed, key, List.last(changed))
          {:changed, before, paragraphs}

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  # [{code, %{key => paragraphs}}] for versions up to `code`, and `code`'s own
  # [{key, paragraphs}] in order
  defp lineage(all_rows, code) do
    rows = Enum.filter(all_rows, &(&1.sections not in [nil, []]))

    case Enum.find_index(rows, &(&1.code == code)) do
      nil ->
        nil

      i ->
        keyed = rows |> Enum.take(i + 1) |> Enum.map(&{&1.code, keyed(&1.sections)})
        {keyed, keyed |> List.last() |> elem(1) |> Map.get(:ordered)}
    end
  end

  # A heading unique in its version is the section's key (so renumbering doesn't
  # break it), also filed under heading@number; a heading several sections share
  # is keyed heading@number (heading#n without numbers), so inserting one doesn't
  # shift the others.
  defp keyed(sections) do
    counts = Enum.frequencies_by(sections, &heading_key/1)

    {ordered, _seen} =
      Enum.map_reduce(sections, %{}, fn section, seen ->
        base = heading_key(section)
        n = Map.get(seen, base, 0) + 1
        numbered = section["enum"] && "#{base}@#{section["enum"]}"

        key =
          cond do
            counts[base] == 1 -> base
            numbered -> numbered
            true -> "#{base}##{n}"
          end

        {{key, Summaries.section_paragraphs(section), numbered}, Map.put(seen, base, n)}
      end)

    entries =
      Enum.flat_map(ordered, fn {key, paragraphs, numbered} ->
        [
          {key, paragraphs}
          | if(numbered && numbered != key, do: [{numbered, paragraphs}], else: [])
        ]
      end)

    entries
    |> Map.new()
    |> Map.put(:ordered, Enum.map(ordered, fn {key, paragraphs, _} -> {key, paragraphs} end))
    # each section's comparable form, worked out once per version
    |> Map.put(
      :normalized,
      Map.new(entries, fn {k, paragraphs} -> {k, normalized(paragraphs)} end)
    )
  end

  defp heading_key(section) do
    case (section["heading"] || "") |> String.downcase() |> String.replace(~r/[^a-z]/, "") do
      "" -> "sec" <> to_string(section["enum"])
      heading -> heading
    end
  end

  defp origin([{first, _} | _] = keyed, key) do
    present = for {code, map} <- keyed, Map.has_key?(map, key), do: {code, normalized(map[key])}
    [{added_in, _} | _] = present

    changed_in =
      present
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.flat_map(fn [{_, a}, {code, b}] -> if a == b, do: [], else: [code] end)

    status =
      cond do
        added_in != first -> :added
        changed_in != [] -> :changed
        true -> :original
      end

    %{status: status, added_in: added_in, changed_in: changed_in}
  end

  # the version before `to` that has the section, with its paragraphs
  defp before_change(keyed, key, to) do
    keyed
    |> Enum.take_while(fn {code, _} -> code != to end)
    |> Enum.filter(fn {_, map} -> Map.has_key?(map, key) end)
    |> List.last()
    |> case do
      nil -> nil
      {code, map} -> {code, map[key]}
    end
  end

  # whether two wordings differ: spaces and clause punctuation (dashes, colons,
  # semicolons, commas) don't count, however the text is split into paragraphs
  defp normalized(paragraphs) do
    paragraphs
    |> Enum.join(" ")
    |> String.split()
    |> Enum.join()
    |> :binary.replace(["—", "–", ":", ";", ","], "", [:global])
  end

  # whitespace, and punctuation where a clause ends ("—" before a list, ":"), don't count
  defp squash(text),
    do: text |> String.replace(~r/[\s—–:;,]+$/u, "") |> String.replace(~r/\s+/u, "")

  # The text split into clauses at its own numbering — "(a)", "(1)", "(A)",
  # "(ii)" — within each paragraph, since versions of the same text are not
  # always split into paragraphs the same way. A clause starts after clause
  # punctuation (or "; and", "; or"), or run straight onto a word when a
  # capitalized word follows ("investments(a)Conduct"); never mid-sentence, so
  # "subsection (b)(2)" and "(EPA)" stay put.
  @enum "\\((?:\\d{1,3}|[a-z]{1,4}|[A-Z]{1,4})\\)"
  @clause_start Regex.compile!(
                  "(?:(?<=[—–:;.])|(?<=; and)|(?<=; or))\\s*(?=#{@enum}\\s?[A-Za-z])|(?<=[a-z])(?=#{@enum}[A-Z][a-z])",
                  "u"
                )

  defp clauses(paragraphs) do
    paragraphs
    |> Enum.flat_map(&String.split(&1, @clause_start))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Clauses aligned by content; a run of removed clauses against a run of added
  # ones is compared word by word as one passage.
  defp diff(before, after_) do
    {before, after_} = {clauses(before), clauses(after_)}

    before
    |> Enum.map(&squash/1)
    |> List.myers_difference(Enum.map(after_, &squash/1))
    |> paragraph_runs(before, after_)
  end

  defp paragraph_runs(edits, before, after_) do
    {runs, _, _} =
      Enum.reduce(edits, {[], before, after_}, fn
        {:eq, keys}, {acc, b, a} ->
          n = length(keys)
          {acc ++ Enum.map(Enum.take(a, n), &[{:eq, &1}]), Enum.drop(b, n), Enum.drop(a, n)}

        {:del, keys}, {acc, b, a} ->
          n = length(keys)
          {acc ++ [{:pending_del, Enum.take(b, n)}], Enum.drop(b, n), a}

        {:ins, keys}, {acc, b, a} ->
          n = length(keys)
          {acc ++ [{:pending_ins, Enum.take(a, n)}], b, Enum.drop(a, n)}
      end)

    merge(runs)
  end

  defp merge([{:pending_del, d}, {:pending_ins, i} | rest]),
    do: passage(Enum.join(d, " "), Enum.join(i, " ")) ++ merge(rest)

  defp merge([{:pending_del, d} | rest]), do: Enum.map(d, &[{:del, &1}]) ++ merge(rest)
  defp merge([{:pending_ins, i} | rest]), do: Enum.map(i, &[{:ins, &1}]) ++ merge(rest)
  defp merge([paragraph | rest]), do: [paragraph | merge(rest)]
  defp merge([]), do: []

  # word marks cost the product of the two lengths, so a long rewrite is shown
  # as its old and new wording whole
  @max_tokens 3_000

  defp passage(a, b) do
    {ta, tb} = {tokens(a), tokens(b)}

    if length(ta) + length(tb) > @max_tokens,
      do: [[{:del, a}], [{:ins, b}]],
      else: [words(ta, tb)]
  end

  defp words(a, b) when is_list(a) do
    a
    |> List.myers_difference(b)
    |> Enum.map(fn {op, toks} -> {op, Enum.join(toks)} end)
    |> join_spaces()
  end

  defp tokens(text), do: Regex.scan(~r/\w+|\s+|[^\w\s]+/u, text) |> List.flatten()

  # a lone space between two edits of the same kind joins them ("; and")
  defp join_spaces([{op, a}, {:eq, space}, {op, b} | rest]) when op != :eq and space in [" "],
    do: join_spaces([{op, a <> space <> b} | rest])

  defp join_spaces([x | rest]), do: [x | join_spaces(rest)]
  defp join_spaces([]), do: []

  defp version_list(%{id: bill_id}) do
    from(v in BillVersion,
      where: v.bill_id == ^bill_id,
      order_by: [asc_nulls_last: v.date, asc: v.id],
      select: %{code: v.code, classification: v.classification, date: v.date}
    )
    |> Repo.all()
  end

  defp rows(%{id: bill_id}) do
    from(v in BillVersion,
      where: v.bill_id == ^bill_id,
      order_by: [asc_nulls_last: v.date, asc: v.id],
      select: %{
        code: v.code,
        classification: v.classification,
        date: v.date,
        sections: v.sections
      }
    )
    |> Repo.all()
  end
end
