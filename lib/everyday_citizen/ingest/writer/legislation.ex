defmodule EverydayCitizen.Ingest.Writer.Legislation do
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
  import Ecto.Changeset, only: [changed?: 2]

  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Ingest.Writer.Support
  alias EverydayCitizen.Jobs.ComputeOrigins

  alias EverydayCitizen.Legislation.{
    Bill,
    BillAction,
    BillAmendment,
    BillCommitteeActivity,
    BillRelation,
    BillSummary,
    BillTitle,
    BillVersion,
    Sponsorship
  }

  alias EverydayCitizen.Legislature.Body
  alias EverydayCitizen.Legislature.Session
  alias EverydayCitizen.Repo

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

  defp do_write(%Records.BillCommittees{} = r, source_id) do
    replace_set(r, BillCommitteeActivity, fn j, bill ->
      for a <- r.activities do
        %{
          bill_id: bill.id,
          body_id: body_id(j.id, a.body_external_id),
          body_ref: a.body_external_id,
          kind: a.kind,
          date: a.date,
          source_id: source_id
        }
      end
    end)
  end

  defp do_write(%Records.BillRelations{} = r, source_id) do
    replace_set(r, BillRelation, fn _j, bill ->
      for rel <- r.relations,
          do: %{
            bill_id: bill.id,
            related_ref: rel.bill_external_id,
            kind: rel.kind,
            source_id: source_id
          }
    end)
  end

  defp do_write(%Records.BillTitles{} = r, source_id) do
    replace_set(r, BillTitle, fn _j, bill ->
      for t <- r.titles,
          do: %{bill_id: bill.id, title: t.title, kind: t.kind, source_id: source_id}
    end)
  end

  defp do_write(%Records.BillAmendments{} = r, source_id) do
    replace_set(r, BillAmendment, fn _j, bill ->
      for a <- r.amendments do
        a
        |> Map.take([
          :external_id,
          :identifier,
          :description,
          :latest_action,
          :latest_action_date,
          :url,
          :agreed
        ])
        |> Map.update(:agreed, false, &(&1 == true))
        |> Map.merge(%{bill_id: bill.id, source_id: source_id})
      end
    end)
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
         {:ok, bill} <- bill(j, r.bill_external_id),
         stored = stored_date(bill.id, r.code),
         {:ok, version} <- upsert_version(r, bill, source_id) do
      # a new version, or one moved in date order, changes where sections came from
      if stored != {:ok, r.date}, do: {:ok, _} = ComputeOrigins.enqueue(bill.id)
      {:ok, version}
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
      changeset =
        BillVersion.text_changeset(version, %{
          xml: r.xml,
          xml_schema: r.xml_schema,
          plain_text: r.plain_text,
          sections: r.sections,
          sections_version: r.sections_version,
          text_source_id: source_id
        })

      changeset |> Repo.update() |> enqueue_origins(bill.id, changed?(changeset, :sections))
    end
  end

  # new sections change where the bill's sections came from
  defp enqueue_origins({:ok, _} = written, bill_id, true) do
    {:ok, _} = ComputeOrigins.enqueue(bill_id)
    written
  end

  defp enqueue_origins(result, _bill_id, _changed), do: result

  defp stored_date(bill_id, code) do
    case Repo.one(
           from v in BillVersion,
             where: v.bill_id == ^bill_id and v.code == ^code,
             select: {v.id, v.date}
         ) do
      {_id, date} -> {:ok, date}
      nil -> :none
    end
  end

  defp upsert_version(r, bill, source_id) do
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
      replace: {:replace, [:classification, :date, :xml_url, :text_url, :source_id, :updated_at]}
    )
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

  # A set with no natural key (committee steps, relations, amendments): the
  # bill's rows are replaced wholesale.
  defp replace_set(r, schema, rows_fun) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, bill} <- bill(j, r.bill_external_id) do
      now = DateTime.utc_now()

      rows =
        j |> rows_fun.(bill) |> Enum.map(&Map.merge(&1, %{inserted_at: now, updated_at: now}))

      Repo.delete_all(from x in schema, where: x.bill_id == ^bill.id)

      # in batches, under the database's limit on parameters per statement
      count =
        rows
        |> Enum.chunk_every(1000)
        |> Enum.reduce(0, fn batch, n -> n + elem(Repo.insert_all(schema, batch), 0) end)

      {:ok, %{written: count}}
    end
  end

  defp body_id(_jurisdiction_id, nil), do: nil

  defp body_id(jurisdiction_id, external_id) do
    Repo.one(
      from b in Body,
        where: b.jurisdiction_id == ^jurisdiction_id and b.external_id == ^external_id,
        select: b.id
    )
  end
end
