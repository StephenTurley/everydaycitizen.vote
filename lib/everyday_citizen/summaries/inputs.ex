defmodule EverydayCitizen.Summaries.Inputs do
  @moduledoc """
  What a bill or week summary is written from, with its subject (the cache
  key): a bill's newest version's full text, subject `"bill:<id>:<code>"`; a
  rep's week of activity, subject `"rep_week:<person id>:<monday>"`. The job
  rebuilds the input from the subject, so it summarizes what is stored now.
  """
  import Ecto.Query

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

  def input(_kind, _subject), do: nil
end
