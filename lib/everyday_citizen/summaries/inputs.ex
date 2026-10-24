defmodule EverydayCitizen.Summaries.Inputs do
  @moduledoc """
  What a bill or week summary is written from, with its subject (the cache
  key): a bill's newest version's full text, subject `"bill:<id>:<code>"`; a
  rep's week of activity, subject `"rep_week:<person id>:<monday>"`. The job
  rebuilds the input from the subject, so it summarizes what is stored now.
  """
  import Ecto.Query

  alias EverydayCitizen.Activity
  alias EverydayCitizen.Activity.Item
  alias EverydayCitizen.Legislation.BillVersion
  alias EverydayCitizen.Repo

  @doc "The bill's newest version with text, as `{subject, full text}`, or nil."
  @spec bill(map()) :: {String.t(), String.t()} | nil
  def bill(%{id: bill_id}) do
    Repo.one(
      from v in BillVersion,
        where: v.bill_id == ^bill_id and not is_nil(v.plain_text) and v.plain_text != "",
        order_by: [desc_nulls_last: v.date, desc: v.id],
        limit: 1,
        select: {v.code, v.plain_text}
    )
    |> case do
      {code, text} -> {"bill:#{bill_id}:#{code}", text}
      nil -> nil
    end
  end

  @doc "The input for a subject, rebuilt from what is stored now (nil if none)."
  @spec input(String.t(), String.t()) :: String.t() | nil
  def input("bill", "bill:" <> rest) do
    with [id, code] <- String.split(rest, ":", parts: 2),
         {bill_id, ""} <- Integer.parse(id) do
      Repo.one(
        from v in BillVersion,
          where: v.bill_id == ^bill_id and v.code == ^code,
          select: v.plain_text
      )
    else
      _ -> nil
    end
  end

  def input("rep_week", "rep_week:" <> rest) do
    with [id, monday] <- String.split(rest, ":", parts: 2),
         {person_id, ""} <- Integer.parse(id),
         {:ok, monday} <- Date.from_iso8601(monday) do
      rep_week(person_id, monday) |> elem(1)
    else
      _ -> nil
    end
  end

  def input(_kind, _subject), do: nil

  @doc """
  A rep's week from Monday: `{subject, lines}`, one line per item (date, what
  they did, the bill, and for votes the question and result), or nil lines for
  a week with nothing on the record.
  """
  @spec rep_week(integer(), Date.t()) :: {String.t(), String.t() | nil}
  def rep_week(person_id, %Date{} = monday) do
    items = Activity.feed(person_id, from: monday, to: Date.add(monday, 6), limit: 500).items
    lines = if items == [], do: nil, else: items |> Enum.reverse() |> Enum.map_join("\n", &line/1)
    {"rep_week:#{person_id}:#{monday}", lines}
  end

  defp line(%Item{date: date} = item),
    do:
      Enum.join(
        [Calendar.strftime(date, "%a %b %-d"), what(item), bill_label(item.bill), detail(item)]
        |> Enum.reject(&is_nil/1),
        " — "
      )

  defp what(%Item{kind: :vote, option: option}), do: "Voted #{option || "—"}"
  defp what(%Item{kind: :introduced}), do: "Introduced"
  defp what(%Item{kind: :moved}), do: "Their bill moved"
  defp what(%Item{kind: :became_law}), do: "Their bill became law"

  defp bill_label(nil), do: nil
  defp bill_label(bill), do: "#{bill.identifier} (#{bill.title})"

  defp detail(%Item{kind: :vote, vote: vote}) when not is_nil(vote),
    do:
      "#{vote.question}#{if vote.description, do: " (#{vote.description})"}: #{vote.result}, #{vote.yea_count}–#{vote.nay_count}"

  defp detail(%Item{kind: :moved, action: action}) when not is_nil(action), do: action.description
  defp detail(_item), do: nil
end
