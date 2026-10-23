defmodule TheFloor.Ingest.Writer.Legislature do
  @moduledoc """
  Persists legislature records. Idempotent: every write is an upsert on the
  natural key, and each row points at its provenance `source`.
  """
  import Ecto.Query

  alias TheFloor.Ingest.Records
  alias TheFloor.Ingest.Writer.Support
  alias TheFloor.Legislature.{Body, Jurisdiction, Membership, Person, PersonIdentifier, Session}
  alias TheFloor.Repo

  import Support, only: [fetch: 4, fetch_person: 2, jurisdiction: 1, upsert: 3]

  @spec write(struct(), integer() | nil) :: {:ok, struct()} | {:error, term()}
  def write(record, run_id) do
    Support.transact(record, run_id, &do_write(record, &1))
  end

  defp do_write(%Records.Jurisdiction{} = r, source_id) do
    upsert(
      Jurisdiction,
      %{key: r.key, name: r.name, classification: r.classification, source_id: source_id},
      [:key]
    )
  end

  defp do_write(%Records.Body{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, parent} <- parent(Body, j.id, :external_id, r.parent_external_id) do
      upsert(
        Body,
        %{
          jurisdiction_id: j.id,
          parent_id: parent && parent.id,
          external_id: r.external_id,
          name: r.name,
          classification: r.classification,
          source_id: source_id
        },
        [:jurisdiction_id, :external_id]
      )
    end
  end

  defp do_write(%Records.LegislativeSession{} = r, source_id) do
    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, parent} <- parent(Session, j.id, :identifier, r.parent_identifier) do
      upsert(
        Session,
        %{
          jurisdiction_id: j.id,
          parent_id: parent && parent.id,
          identifier: r.identifier,
          name: r.name,
          start_date: r.start_date,
          end_date: r.end_date,
          source_id: source_id
        },
        [:jurisdiction_id, :identifier]
      )
    end
  end

  defp do_write(%Records.Person{} = r, source_id) do
    attrs = %{
      name: r.name,
      given_name: r.given_name,
      family_name: r.family_name,
      image_url: r.image_url,
      source_id: source_id
    }

    with {:ok, person} <- upsert_person(find_person(r.identifiers), attrs),
         :ok <- add_identifiers(person, r.identifiers, source_id) do
      {:ok, person}
    end
  end

  defp do_write(%Records.Membership{} = r, source_id) do
    {scheme, value} = r.person

    with {:ok, j} <- jurisdiction(r.jurisdiction),
         {:ok, body} <-
           fetch(
             Body,
             [jurisdiction_id: j.id, external_id: r.body_external_id],
             :unknown_body,
             r.body_external_id
           ),
         {:ok, person} <- fetch_person(scheme, value) do
      upsert(
        Membership,
        %{
          person_id: person.id,
          body_id: body.id,
          role: r.role,
          party: r.party,
          district: r.district,
          start_date: r.start_date,
          end_date: r.end_date,
          source_id: source_id
        },
        [:person_id, :body_id, :role, :start_date]
      )
    end
  end

  defp parent(_schema, _jurisdiction_id, _field, nil), do: {:ok, nil}

  defp parent(schema, jurisdiction_id, field, value) do
    fetch(schema, [{:jurisdiction_id, jurisdiction_id}, {field, value}], :unknown_parent, value)
  end

  defp find_person(identifiers) do
    Person
    |> join(:inner, [p], i in PersonIdentifier, on: i.person_id == p.id)
    |> where(
      [_p, i],
      ^Enum.reduce(identifiers, dynamic(false), fn {s, v}, acc ->
        dynamic([_p, i], ^acc or (i.scheme == ^s and i.value == ^v))
      end)
    )
    |> order_by([p], asc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  defp upsert_person(existing, attrs) do
    (existing || %Person{})
    |> Person.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp add_identifiers(person, identifiers, source_id) do
    Enum.each(identifiers, fn {scheme, value} ->
      Repo.insert!(
        PersonIdentifier.changeset(%PersonIdentifier{}, %{
          person_id: person.id,
          scheme: scheme,
          value: value,
          source_id: source_id
        }),
        on_conflict: :nothing,
        conflict_target: [:scheme, :value]
      )
    end)
  end
end
