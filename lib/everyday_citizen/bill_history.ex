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

  alias EverydayCitizen.Legislation.BillVersion
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Summaries

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
  def versions(bill), do: bill |> rows() |> Enum.map(&Map.delete(&1, :sections))

  @doc "Where each section of version `code` came from, by its index; `%{}` with fewer than two versions to compare."
  @spec origins(map(), String.t()) :: %{non_neg_integer() => origin()}
  def origins(bill, code) do
    case lineage(bill, code) do
      {[_, _ | _] = keyed, target} ->
        target |> Enum.with_index() |> Map.new(fn {{key, _}, i} -> {i, origin(keyed, key)} end)

      _ ->
        %{}
    end
  end

  @doc """
  Section `index` of version `code` against its wording before its most recent
  change: `%{from, to, paragraphs}`, each paragraph a list of `{:eq | :del | :ins,
  text}`. nil for a section never changed (or added and never changed since).
  """
  @spec comparison(map(), String.t(), non_neg_integer()) ::
          %{from: String.t(), to: String.t(), paragraphs: [[op()]]} | nil
  def comparison(bill, code, index) do
    with {[_, _ | _] = keyed, target} <- lineage(bill, code),
         {key, paragraphs} <- Enum.at(target, index),
         %{changed_in: [_ | _] = changed} <- origin(keyed, key),
         to = List.last(changed),
         {from, before} <- before_change(keyed, key, to) do
      %{from: from, to: to, paragraphs: diff(before, paragraphs)}
    else
      _ -> nil
    end
  end

  # [{code, %{key => paragraphs}}] for versions up to `code`, and `code`'s own
  # [{key, paragraphs}] in order
  defp lineage(bill, code) do
    rows = Enum.filter(rows(bill), &(&1.sections not in [nil, []]))

    case Enum.find_index(rows, &(&1.code == code)) do
      nil ->
        nil

      i ->
        keyed = rows |> Enum.take(i + 1) |> Enum.map(&{&1.code, keyed(&1.sections)})
        {keyed, keyed |> List.last() |> elem(1) |> Map.get(:ordered)}
    end
  end

  defp keyed(sections) do
    {ordered, _counts} =
      Enum.map_reduce(sections, %{}, fn section, counts ->
        base = key(section)
        n = Map.get(counts, base, 0) + 1
        {{"#{base}##{n}", Summaries.section_paragraphs(section)}, Map.put(counts, base, n)}
      end)

    ordered |> Map.new() |> Map.put(:ordered, ordered)
  end

  defp key(section) do
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

  defp normalized(paragraphs), do: Enum.map(paragraphs, &squash/1)
  defp squash(text), do: String.replace(text, ~r/\s+/u, "")

  # Paragraphs aligned by content; a run of removed paragraphs against a run of
  # added ones is compared word by word as one passage.
  defp diff(before, after_) do
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
    do: [words(Enum.join(d, " "), Enum.join(i, " ")) | merge(rest)]

  defp merge([{:pending_del, d} | rest]), do: Enum.map(d, &[{:del, &1}]) ++ merge(rest)
  defp merge([{:pending_ins, i} | rest]), do: Enum.map(i, &[{:ins, &1}]) ++ merge(rest)
  defp merge([paragraph | rest]), do: [paragraph | merge(rest)]
  defp merge([]), do: []

  defp words(a, b) do
    tokens(a)
    |> List.myers_difference(tokens(b))
    |> Enum.map(fn {op, toks} -> {op, Enum.join(toks)} end)
    |> join_spaces()
  end

  defp tokens(text), do: Regex.scan(~r/\w+|\s+|[^\w\s]+/u, text) |> List.flatten()

  # a lone space between two edits of the same kind joins them ("; and")
  defp join_spaces([{op, a}, {:eq, space}, {op, b} | rest]) when op != :eq and space in [" "],
    do: join_spaces([{op, a <> space <> b} | rest])

  defp join_spaces([x | rest]), do: [x | join_spaces(rest)]
  defp join_spaces([]), do: []

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
