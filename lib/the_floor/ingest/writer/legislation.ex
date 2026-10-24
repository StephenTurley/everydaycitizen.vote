defmodule TheFloor.Ingest.Writer.Legislation do
  @moduledoc """
  Persists bills and their dependent rows. Idempotent: every write is an upsert on
  a natural key, and each row points at its provenance `source`.

  `BillActions` and `Sponsorships` replace the bill's full set: inside one
  transaction the incoming rows are upserted and the bill's other rows deleted.

  Natural keys:

    * bill: `(jurisdiction, external_id)`
    * action: `(bill, position)` — `position` is the action's order in the source
      list, so a re-ingest that edits an action updates its row in place
    * sponsorship: `(bill, person, classification)`
    * version: `(bill, code)`; text arrives separately and is stored in the same
      row, with its own `text_source_id`. Re-ingesting version metadata never
      clears stored text.

  Returns `{:ok, row}` for bills and versions, `{:ok, %{written: n}}` for actions,
  `{:ok, %{written: n, skipped_people: [ref]}}` for sponsorships (people not yet
  known are skipped, not fatal), or `{:error, {:unknown_*, value}}`.
  """
  import Ecto.Query

  alias TheFloor.Ingest.Records
  alias TheFloor.Ingest.Writer.Support
  alias TheFloor.Legislation.{Bill, BillAction, BillSummary, BillVersion, Sponsorship}
  alias TheFloor.Legislature.Session
  alias TheFloor.Repo

  import Support,
    only: [body: 2, fetch: 4, fetch_person: 2, jurisdiction: 1, upsert: 3, upsert: 4]

  @spec write(struct(), integer() | nil) :: {:ok, term()} | {:error, term()}
  def write(record, run_id) do
    Support.transact(record, run_id, &do_write(record, &1))
  end

  defp do_write(%Records.Bill{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, session} <-
           fetch(
             Session,
             [jurisdiction_id: j.id, identifier: r.session_identifier],
             :unknown_session,
             r.session_identifier
           ),
         {:ok, from_body} <- body(j.id, r.from_body_external_id) do
      upsert(
        Bill,
        %{
          jurisdiction_id: j.id,
          session_id: session.id,
          from_body_id: from_body && from_body.id,
          external_id: r.external_id,
          web_url: r.web_url,
          identifier: r.identifier,
          classification: r.classification,
          title: r.title,
          subjects: r.subjects,
          introduced_on: r.introduced_on,
          updated_at_source: r.updated_at_source,
          source_id: source_id
        },
        [:jurisdiction_id, :external_id]
      )
    end
  end

  defp do_write(%Records.BillActions{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, bill} <- bill(j, r.bill_external_id),
         {:ok, ids} <- upsert_all(r.actions, &action_row(&1, j, bill, source_id), BillAction) do
      delete_others(BillAction, bill.id, ids)
      {:ok, %{written: length(ids)}}
    end
  end

  defp do_write(%Records.BillSummaries{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, bill} <- bill(j, r.bill_external_id),
         {:ok, ids} <-
           upsert_all(r.summaries, &summary_row(&1, bill, r.author, source_id), BillSummary) do
      delete_others(BillSummary, bill.id, ids)
      {:ok, %{written: length(ids)}}
    end
  end

  defp do_write(%Records.Sponsorships{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, bill} <- bill(j, r.bill_external_id) do
      {known, skipped} = resolve_people(r.sponsorships)

      with {:ok, ids} <-
             upsert_all(known, &sponsorship_row(&1, bill, source_id), Sponsorship) do
        delete_others(Sponsorship, bill.id, ids)
        {:ok, %{written: length(ids), skipped_people: skipped}}
      end
    end
  end

  defp do_write(%Records.BillVersion{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, bill} <- bill(j, r.bill_external_id) do
      upsert(
        BillVersion,
        %{
          bill_id: bill.id,
          code: r.code,
          classification: r.classification,
          date: r.date,
          xml_url: r.xml_url,
          text_url: r.text_url,
          source_id: source_id
        },
        [:bill_id, :code],
        replace:
          {:replace, [:classification, :date, :xml_url, :text_url, :source_id, :updated_at]}
      )
    end
  end

  defp do_write(%Records.BillVersionText{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, bill} <- bill(j, r.bill_external_id),
         {:ok, version} <-
           fetch(
             BillVersion,
             [bill_id: bill.id, code: r.code],
             :unknown_bill_version,
             {r.bill_external_id, r.code}
           ) do
      version
      |> BillVersion.text_changeset(%{
        xml: r.xml,
        xml_schema: r.xml_schema,
        plain_text: r.plain_text,
        sections: r.sections,
        sections_version: r.sections_version,
        text_source_id: source_id
      })
      |> Repo.update()
    end
  end

  defp bill(jurisdiction, external_id) do
    fetch(
      Bill,
      [jurisdiction_id: jurisdiction.id, external_id: external_id],
      :unknown_bill,
      external_id
    )
  end

  defp action_row(a, j, bill, source_id) do
    with {:ok, actor} <- body(j.id, a.actor_body_external_id) do
      {:ok,
       {%{
          bill_id: bill.id,
          actor_body_id: actor && actor.id,
          position: a.position,
          date: a.date,
          description: a.description,
          raw_type: a.raw_type,
          raw_code: a.raw_code,
          classification: a.classification,
          source_id: source_id
        }, [:bill_id, :position]}}
    end
  end

  defp summary_row(s, bill, author, source_id) do
    {:ok,
     {%{
        bill_id: bill.id,
        version_code: s.version_code,
        action_date: s.action_date,
        action_description: s.action_description,
        author: author,
        html: s.html,
        updated_at_source: s.updated_at_source,
        source_id: source_id
      }, [:bill_id, :version_code, :action_date]}}
  end

  defp sponsorship_row({person, s}, bill, source_id) do
    {:ok,
     {%{
        bill_id: bill.id,
        person_id: person.id,
        classification: s.classification,
        date: s[:date],
        withdrawn_on: s[:withdrawn_on],
        source_id: source_id
      }, [:bill_id, :person_id, :classification]}}
  end

  defp resolve_people(sponsorships) do
    {known, skipped} =
      Enum.reduce(sponsorships, {[], []}, fn s, {known, skipped} ->
        {scheme, value} = s.person

        case fetch_person(scheme, value) do
          {:ok, person} -> {[{person, s} | known], skipped}
          {:error, {:unknown_person, ref}} -> {known, [ref | skipped]}
        end
      end)

    {Enum.reverse(known), skipped |> Enum.reverse() |> Enum.uniq()}
  end

  # Upserts each item via `row_fun` (returning `{:ok, {attrs, conflict_target}}`),
  # stopping at the first error; returns the ids of the written rows.
  defp upsert_all(items, row_fun, schema) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, ids} ->
      with {:ok, {attrs, target}} <- row_fun.(item),
           {:ok, row} <- upsert(schema, attrs, target) do
        {:cont, {:ok, [row.id | ids]}}
      else
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp delete_others(schema, bill_id, keep_ids) do
    Repo.delete_all(from r in schema, where: r.bill_id == ^bill_id and r.id not in ^keep_ids)
  end
end
