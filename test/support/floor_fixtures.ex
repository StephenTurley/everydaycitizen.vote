defmodule EverydayCitizen.FloorFixtures do
  @moduledoc """
  A small federal delegation for page tests: Iowa's two senators and its 1st
  District representative, a bill sponsored by a senator with a few actions,
  and a Senate passage vote on it.
  """
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislature

  @src Records.SourceRef.new("https://www.congress.gov/x", "x")

  def iowa! do
    w = fn r ->
      {:ok, row} = Ingest.write(r, nil)
      row
    end

    w.(%Records.Jurisdiction{
      key: "federal",
      name: "United States",
      classification: "federal",
      source: @src
    })

    w.(%Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: @src})

    w.(%Records.LegislativeSession{
      jurisdiction: "federal",
      identifier: "119-2",
      parent_identifier: "119",
      start_date: ~D[2026-01-03],
      source: @src
    })

    for {id, name} <- [{"house", "House of Representatives"}, {"senate", "Senate"}] do
      w.(%Records.Body{
        jurisdiction: "federal",
        external_id: id,
        name: name,
        classification: "chamber",
        source: @src
      })
    end

    for {id, name, body, district} <- [
          {"G000386", "Chuck Grassley", "senate", "IA"},
          {"E000295", "Joni Ernst", "senate", "IA"},
          {"M001215", "Mariannette Miller-Meeks", "house", "IA-1"}
        ] do
      w.(%Records.Person{identifiers: [{"bioguide", id}], name: name, source: @src})

      w.(%Records.Membership{
        jurisdiction: "federal",
        person: {"bioguide", id},
        body_external_id: body,
        role: "member",
        party: "Republican",
        district: district,
        start_date: ~D[2025-01-03],
        end_date: ~D[2031-01-03],
        source: @src
      })
    end

    w.(%Records.Bill{
      jurisdiction: "federal",
      session_identifier: "119",
      external_id: "119-s-5",
      identifier: "S. 5",
      classification: "bill",
      title: "Laken Riley Act",
      from_body_external_id: "senate",
      introduced_on: ~D[2026-01-06],
      source: @src
    })

    w.(%Records.Sponsorships{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      sponsorships: [
        %{
          person: {"bioguide", "E000295"},
          classification: "primary",
          date: ~D[2026-01-06],
          withdrawn_on: nil
        },
        %{
          person: {"bioguide", "G000386"},
          classification: "cosponsor",
          date: ~D[2026-01-06],
          withdrawn_on: nil
        }
      ],
      source: @src
    })

    w.(%Records.BillActions{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      actions: [
        %Records.BillAction{
          position: 0,
          date: ~D[2026-01-06],
          description: "Introduced in Senate",
          classification: "introduced",
          actor_body_external_id: "senate"
        },
        %Records.BillAction{
          position: 1,
          date: ~D[2026-01-20],
          description: "Passed Senate with an amendment by Yea-Nay Vote. 64 - 35.",
          classification: "passed_chamber",
          actor_body_external_id: "senate"
        }
      ],
      source: @src
    })

    w.(%Records.Vote{
      jurisdiction: "federal",
      body_external_id: "senate",
      session_identifier: "119-2",
      external_id: "senate-119-2-7",
      identifier: "Roll Call 7",
      question: "On Passage of the Bill",
      classification: "passage",
      result: "Bill Passed",
      passed: true,
      voted_at: ~U[2026-01-20 17:00:00Z],
      bill_external_id: "119-s-5",
      counts: %{yea: 64, nay: 35, present: 0, absent: 1},
      positions: [
        %{
          person: {"bioguide", "G000386"},
          raw_label: "Grassley",
          option: "yea",
          raw_option: "Yea"
        },
        %{person: {"bioguide", "E000295"}, raw_label: "Ernst", option: "nay", raw_option: "Nay"}
      ],
      source: @src
    })

    %{
      grassley: Legislature.get_person_by_identifier("bioguide", "G000386"),
      ernst: Legislature.get_person_by_identifier("bioguide", "E000295"),
      miller_meeks: Legislature.get_person_by_identifier("bioguide", "M001215")
    }
  end
end
