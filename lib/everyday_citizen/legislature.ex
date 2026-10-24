defmodule EverydayCitizen.Legislature do
  @moduledoc "Queries over legislatures, bodies, sessions, people and memberships."
  import Ecto.Query

  alias EverydayCitizen.Legislature.{
    Body,
    Jurisdiction,
    Membership,
    Person,
    PersonIdentifier,
    Session
  }

  alias EverydayCitizen.Repo

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

  @doc "Person ids for `{scheme, value}` identifiers, keyed by identifier; unknown ones are absent."
  @spec person_ids_by_identifiers([{String.t(), String.t()}]) :: %{
          {String.t(), String.t()} => integer()
        }
  def person_ids_by_identifiers([]), do: %{}

  def person_ids_by_identifiers(identifiers) do
    {schemes, values} = Enum.unzip(identifiers)
    wanted = MapSet.new(identifiers)

    PersonIdentifier
    |> where([i], i.value in ^Enum.uniq(values) and i.scheme in ^Enum.uniq(schemes))
    |> select([i], {{i.scheme, i.value}, i.person_id})
    |> Repo.all()
    |> Enum.filter(fn {key, _id} -> MapSet.member?(wanted, key) end)
    |> Map.new()
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

  @doc """
  Members of each `{body_external_id, district}` seat current on `on`, in seat
  order, then by name, as `%{person, membership, body}`.
  """
  @spec current_members(String.t(), [{String.t(), String.t()}], Date.t()) :: [map()]
  def current_members(_jurisdiction_key, [], _on), do: []

  def current_members(jurisdiction_key, seats, %Date{} = on) do
    rows =
      Membership
      |> join(:inner, [m], b in Body, on: b.id == m.body_id)
      |> join(:inner, [_m, b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
      |> join(:inner, [m], p in Person, on: p.id == m.person_id)
      |> where([_m, _b, j], j.key == ^jurisdiction_key)
      |> where(^seat_condition(seats))
      |> where([m], is_nil(m.start_date) or m.start_date <= ^on)
      |> where([m], is_nil(m.end_date) or m.end_date >= ^on)
      |> select([m, b, _j, p], %{person: p, membership: m, body: b})
      |> Repo.all()

    rank = seats |> Enum.with_index() |> Map.new()

    rows
    |> Enum.uniq_by(& &1.person.id)
    |> Enum.sort_by(
      &{Map.fetch!(rank, {&1.body.external_id, &1.membership.district}), &1.person.name}
    )
  end

  defp seat_condition(seats) do
    Enum.reduce(seats, dynamic(false), fn {body, district}, acc ->
      dynamic([m, b], ^acc or (b.external_id == ^body and m.district == ^district))
    end)
  end

  @doc "District keys overlapping a postal code, largest share of its land first."
  @spec postal_districts(String.t(), String.t()) :: [String.t()]
  def postal_districts(jurisdiction_key, postal_code) do
    EverydayCitizen.Legislature.PostalDistrict
    |> join(:inner, [p], j in Jurisdiction, on: j.id == p.jurisdiction_id)
    |> where([p, j], j.key == ^jurisdiction_key and p.postal_code == ^postal_code)
    |> order_by([p], desc: p.land_share, asc: p.district_key)
    |> select([p], p.district_key)
    |> Repo.all()
  end
end
