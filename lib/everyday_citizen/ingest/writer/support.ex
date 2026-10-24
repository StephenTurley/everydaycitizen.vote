defmodule EverydayCitizen.Ingest.Writer.Support do
  @moduledoc """
  Helpers shared by the ingest writers: the transactional write wrapper (which
  upserts the record's provenance source first), tagged lookups and upserts.
  """
  alias EverydayCitizen.Legislature.{Body, Jurisdiction}
  alias EverydayCitizen.Provenance
  alias EverydayCitizen.Repo

  @replace_all {:replace_all_except, [:id, :inserted_at]}

  @doc """
  Runs `fun.(source_id)` in a transaction after upserting the record's source.
  `fun` returns `{:ok, value}` or `{:error, reason}`; an error rolls everything back.
  """
  @spec transact(struct(), integer() | nil, (integer() -> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def transact(record, run_id, fun) do
    Repo.transaction(fn ->
      {:ok, source} = Provenance.upsert_source(record.source, run_id)

      case fun.(source.id) do
        {:ok, value} -> value
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @spec jurisdiction(String.t()) :: {:ok, Jurisdiction.t()} | {:error, term()}
  def jurisdiction(key), do: fetch(Jurisdiction, [key: key], :unknown_jurisdiction, key)

  @doc "Finds a body of the jurisdiction by external id; a nil id yields `{:ok, nil}`."
  @spec body(integer(), String.t() | nil) :: {:ok, Body.t() | nil} | {:error, term()}
  def body(_jurisdiction_id, nil), do: {:ok, nil}

  def body(jurisdiction_id, external_id) do
    fetch(
      Body,
      [jurisdiction_id: jurisdiction_id, external_id: external_id],
      :unknown_body,
      external_id
    )
  end

  @spec fetch(module(), keyword(), atom(), term()) :: {:ok, struct()} | {:error, term()}
  def fetch(schema, clauses, error_tag, error_value) do
    case Repo.get_by(schema, clauses) do
      nil -> {:error, {error_tag, error_value}}
      row -> {:ok, row}
    end
  end

  @spec fetch_person(String.t(), String.t()) :: {:ok, struct()} | {:error, term()}
  def fetch_person(scheme, value) do
    case EverydayCitizen.Legislature.get_person_by_identifier(scheme, value) do
      nil -> {:error, {:unknown_person, {scheme, value}}}
      person -> {:ok, person}
    end
  end

  @doc """
  Inserts the row, or on conflict with `conflict_target` replaces its columns
  (all but `id`/`inserted_at` unless `:replace` gives an Ecto `on_conflict` replace option).
  """
  @spec upsert(module(), map(), [atom()], keyword()) ::
          {:ok, struct()} | {:error, Ecto.Changeset.t()}
  def upsert(schema, attrs, conflict_target, opts \\ []) do
    Repo.insert(schema.changeset(struct(schema), attrs),
      on_conflict: Keyword.get(opts, :replace, @replace_all),
      conflict_target: conflict_target,
      returning: true
    )
  end
end
