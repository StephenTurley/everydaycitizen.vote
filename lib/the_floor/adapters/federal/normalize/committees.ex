defmodule TheFloor.Adapters.Federal.Normalize.Committees do
  @moduledoc """
  Normalizes committees and committee membership from unitedstates/congress-legislators.
  External ids match Congress.gov `systemCode` (`hsag00`, subcommittee `hsag03`).
  Membership dates are nil: the source only lists current members.
  """
  alias TheFloor.Ingest.Records.{Body, Membership, SourceRef}

  @jurisdiction "federal"

  @spec records([map()], %{String.t() => [map()]}, SourceRef.t()) :: [Body.t() | Membership.t()]
  def records(committees, memberships, %SourceRef{} = source) do
    bodies =
      Enum.flat_map(committees, fn committee ->
        parent_code = committee["thomas_id"]
        parent_id = String.downcase(parent_code) <> "00"

        subs =
          for sub <- committee["subcommittees"] || [] do
            body(
              String.downcase(parent_code <> sub["thomas_id"]),
              sub["name"],
              "subcommittee",
              parent_id,
              source
            )
          end

        [
          body(parent_id, committee["name"], "committee", chamber(committee["type"]), source)
          | subs
        ]
      end)

    known = MapSet.new(bodies, & &1.external_id)

    seats =
      for {code, members} <- Enum.sort(memberships),
          external_id = external_id(code),
          external_id in known,
          member <- members,
          member["bioguide"] do
        %Membership{
          jurisdiction: @jurisdiction,
          person: {"bioguide", member["bioguide"]},
          body_external_id: external_id,
          role: role(member["title"]),
          source: source
        }
      end

    bodies ++ seats
  end

  # Top-level committee codes are four letters; subcommittee codes append two digits.
  defp external_id(code) when byte_size(code) == 4, do: String.downcase(code) <> "00"
  defp external_id(code), do: String.downcase(code)

  defp body(external_id, name, classification, parent, source) do
    %Body{
      jurisdiction: @jurisdiction,
      external_id: external_id,
      name: name,
      classification: classification,
      parent_external_id: parent,
      source: source
    }
  end

  defp chamber("house"), do: "house"
  defp chamber("senate"), do: "senate"
  defp chamber("joint"), do: "congress"

  defp role(nil), do: "member"
  defp role("Ranking Member"), do: "ranking_member"
  defp role("Vice" <> _), do: "vice_chair"
  defp role("Chair" <> _), do: "chair"
  defp role("Cochairman"), do: "chair"
  defp role(_), do: "member"
end
