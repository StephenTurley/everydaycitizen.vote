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

  # the largest id the database can hold
  @max_id 9_223_372_036_854_775_807

  @doc "A person by id, given as an integer or its decimal string; nil for anything else."
  @spec get_person(String.t() | integer()) :: Person.t() | nil
  def get_person(id) when is_integer(id) and id > 0 and id <= @max_id, do: Repo.get(Person, id)

  def get_person(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} when int > 0 and int <= @max_id -> get_person(int)
      _ -> nil
    end
  end

  def get_person(_id), do: nil

  @doc """
  A person's most recent chamber membership, ended or not, with its body; nil
  when they have none.
  """
  @spec latest_chamber_membership(integer()) ::
          %{membership: Membership.t(), body: Body.t()} | nil
  def latest_chamber_membership(person_id) do
    from(m in Membership,
      join: b in Body,
      on: b.id == m.body_id,
      where: m.person_id == ^person_id and b.classification == "chamber",
      order_by: [desc_nulls_last: m.start_date, desc: m.id],
      limit: 1,
      select: %{membership: m, body: b}
    )
    |> Repo.one()
  end

  @doc "The earliest start date of a person's memberships in a body; nil when none is known."
  @spec serving_since(integer(), integer()) :: Date.t() | nil
  def serving_since(person_id, body_id) do
    Membership
    |> where([m], m.person_id == ^person_id and m.body_id == ^body_id)
    |> select([m], min(m.start_date))
    |> Repo.one()
  end

  @doc """
  A person's committee and subcommittee seats current on `on`, as `%{body,
  role}`: each committee by name, followed by its subcommittees by name.
  """
  @spec committee_roles(integer(), Date.t()) :: [%{body: Body.t(), role: String.t()}]
  def committee_roles(person_id, %Date{} = on) do
    from(m in Membership,
      join: b in Body,
      on: b.id == m.body_id,
      left_join: parent in Body,
      on: parent.id == b.parent_id,
      where: m.person_id == ^person_id and b.classification in ["committee", "subcommittee"],
      where: is_nil(m.start_date) or m.start_date <= ^on,
      where: is_nil(m.end_date) or m.end_date >= ^on,
      select: {%{body: b, role: m.role}, parent.name}
    )
    |> Repo.all()
    |> Enum.uniq_by(fn {%{body: b}, _} -> b.id end)
    |> Enum.sort_by(fn
      {%{body: %{classification: "committee", name: name}}, _} -> {name, 0, ""}
      {%{body: %{name: name}}, parent} -> {parent || name, 1, name}
    end)
    |> Enum.map(&elem(&1, 0))
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

  @doc """
  Members current on `on` of each `{body_external_id, {:exact | :prefix, text}}`
  seat, as `%{person, membership, body}`: in seat order, then by district number
  ("2" before "10"), then by name.
  """
  @spec current_members_matching(
          String.t(),
          [{String.t(), {:exact | :prefix, String.t()}}],
          Date.t()
        ) ::
          [map()]
  def current_members_matching(_jurisdiction_key, [], _on), do: []

  def current_members_matching(jurisdiction_key, seats, %Date{} = on) do
    rows =
      Membership
      |> join(:inner, [m], b in Body, on: b.id == m.body_id)
      |> join(:inner, [_m, b], j in Jurisdiction, on: j.id == b.jurisdiction_id)
      |> join(:inner, [m], p in Person, on: p.id == m.person_id)
      |> where([_m, _b, j], j.key == ^jurisdiction_key)
      |> where(^matcher_condition(seats))
      |> where([m], is_nil(m.start_date) or m.start_date <= ^on)
      |> where([m], is_nil(m.end_date) or m.end_date >= ^on)
      |> select([m, b, _j, p], %{person: p, membership: m, body: b})
      |> Repo.all()

    rows
    |> Enum.uniq_by(& &1.person.id)
    |> Enum.sort_by(
      &{seat_rank(seats, &1), district_number(&1.membership.district), &1.person.name}
    )
  end

  defp matcher_condition(seats) do
    Enum.reduce(seats, dynamic(false), fn
      {body, {:exact, district}}, acc ->
        dynamic([m, b], ^acc or (b.external_id == ^body and m.district == ^district))

      {body, {:prefix, prefix}}, acc ->
        like = escape_like(prefix) <> "%"
        dynamic([m, b], ^acc or (b.external_id == ^body and like(m.district, ^like)))
    end)
  end

  defp escape_like(text), do: String.replace(text, ["\\", "%", "_"], &"\\#{&1}")

  defp seat_rank(seats, %{body: body, membership: membership}) do
    Enum.find_index(seats, fn
      {id, {:exact, district}} ->
        id == body.external_id and membership.district == district

      {id, {:prefix, prefix}} ->
        id == body.external_id and String.starts_with?(membership.district || "", prefix)
    end)
  end

  # the trailing integer of a district key; seats without one come first
  defp district_number(nil), do: 0

  defp district_number(district) do
    case Regex.run(~r/(\d+)$/, district) do
      [_, n] -> String.to_integer(n)
      nil -> 0
    end
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
