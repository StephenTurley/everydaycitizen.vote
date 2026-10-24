defmodule EverydayCitizen.Adapters.Federal.Normalize.Members do
  @moduledoc """
  Normalizes unitedstates/congress-legislators entries into people and chamber
  memberships (one per term overlapping the session). Legislators with no
  overlapping term are dropped, which also filters the large historical file.
  """
  alias EverydayCitizen.Ingest.Records.{Membership, Person, SourceRef}

  @jurisdiction "federal"
  @schemes ~w(bioguide lis govtrack thomas)

  @spec records([map()], Date.t(), SourceRef.t()) :: [Person.t() | Membership.t()]
  def records(legislators, %Date{} = session_start, %SourceRef{} = source) do
    in_range =
      for legislator <- legislators,
          terms = Enum.filter(legislator["terms"] || [], &overlaps?(&1, session_start)),
          terms != [],
          identifiers = identifiers(legislator["id"]),
          identifiers != [] do
        {legislator, identifiers, terms}
      end

    people = for {l, ids, _} <- in_range, do: person(l, ids, source)

    memberships =
      for {_, ids, terms} <- in_range, term <- terms, do: membership(hd(ids), term, source)

    people ++ memberships
  end

  defp overlaps?(%{"end" => end_date}, session_start),
    do: Date.compare(Date.from_iso8601!(end_date), session_start) != :lt

  defp identifiers(ids) do
    for scheme <- @schemes, value = ids[scheme], not is_nil(value), do: {scheme, to_string(value)}
  end

  defp person(legislator, identifiers, source) do
    name = legislator["name"] || %{}

    %Person{
      identifiers: identifiers,
      name: name["official_full"] || String.trim("#{name["first"]} #{name["last"]}"),
      given_name: name["first"],
      family_name: name["last"],
      source: source
    }
  end

  defp membership(person_ref, term, source) do
    %Membership{
      jurisdiction: @jurisdiction,
      person: person_ref,
      body_external_id: body(term["type"]),
      role: "member",
      party: term["party"],
      district: district(term),
      start_date: Date.from_iso8601!(term["start"]),
      end_date: Date.from_iso8601!(term["end"]),
      source: source
    }
  end

  defp body("rep"), do: "house"
  defp body("sen"), do: "senate"

  defp district(%{"type" => "rep", "state" => state, "district" => 0}), do: "#{state}-AL"
  defp district(%{"type" => "rep", "state" => state, "district" => n}), do: "#{state}-#{n}"
  defp district(%{"type" => "sen", "state" => state}), do: state
end
