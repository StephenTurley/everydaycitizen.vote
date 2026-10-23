defmodule TheFloor.Legislature do
  @moduledoc "Queries over legislatures, bodies, sessions, people and memberships."
  import Ecto.Query

  alias TheFloor.Legislature.{Body, Jurisdiction, Membership, Person, PersonIdentifier, Session}
  alias TheFloor.Repo

  @spec get_jurisdiction!(String.t()) :: Jurisdiction.t()
  def get_jurisdiction!(key), do: Repo.get_by!(Jurisdiction, key: key)

  @spec get_body(String.t(), String.t()) :: Body.t() | nil
  def get_body(jurisdiction_key, external_id) do
    Body
    |> join(:inner, [b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
    |> where([b, j], j.key == ^jurisdiction_key and b.external_id == ^external_id)
    |> Repo.one()
  end

  @spec get_session(String.t(), String.t()) :: Session.t() | nil
  def get_session(jurisdiction_key, identifier) do
    Session
    |> join(:inner, [s], j in Jurisdiction, on: j.id == s.jurisdiction_id)
    |> where([s, j], j.key == ^jurisdiction_key and s.identifier == ^identifier)
    |> Repo.one()
  end

  @doc "Sessions nested directly under the session with the given identifier."
  @spec child_sessions(String.t(), String.t()) :: [Session.t()]
  def child_sessions(jurisdiction_key, parent_identifier) do
    Session
    |> join(:inner, [s], j in Jurisdiction, on: j.id == s.jurisdiction_id)
    |> join(:inner, [s], p in Session, on: p.id == s.parent_id)
    |> where([s, j, p], j.key == ^jurisdiction_key and p.identifier == ^parent_identifier)
    |> order_by([s], s.identifier)
    |> Repo.all()
  end

  @spec get_person_by_identifier(String.t(), String.t()) :: Person.t() | nil
  def get_person_by_identifier(scheme, value) do
    Person
    |> join(:inner, [p], i in PersonIdentifier, on: i.person_id == p.id)
    |> where([_p, i], i.scheme == ^scheme and i.value == ^value)
    |> Repo.one()
  end

  @spec any_person?() :: boolean()
  def any_person?, do: Repo.exists?(Person)

  @doc "True when the jurisdiction has a body of one of the classifications."
  @spec any_body?(String.t(), [String.t()]) :: boolean()
  def any_body?(jurisdiction_key, classifications) do
    Body
    |> join(:inner, [b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
    |> where([b, j], j.key == ^jurisdiction_key and b.classification in ^classifications)
    |> Repo.exists?()
  end

  @doc "Memberships of the body that have started and not ended on the given date."
  @spec current_memberships(integer(), Date.t()) :: [Membership.t()]
  def current_memberships(body_id, %Date{} = on) do
    Membership
    |> where([m], m.body_id == ^body_id)
    |> where([m], is_nil(m.start_date) or m.start_date <= ^on)
    |> where([m], is_nil(m.end_date) or m.end_date >= ^on)
    |> order_by([m], asc: m.id)
    |> Repo.all()
  end
end
