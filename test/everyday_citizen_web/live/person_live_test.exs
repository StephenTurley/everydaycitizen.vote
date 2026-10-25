defmodule EverydayCitizenWeb.PersonLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true

  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest

  alias EverydayCitizen.{Ingest, Legislation, Legislature}
  alias EverydayCitizen.Ingest.Records

  @src Records.SourceRef.new("https://x.test/person-live", "p")

  setup do
    {:ok, EverydayCitizen.FloorFixtures.iowa!()}
  end

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  defp committees! do
    for {id, name, class, parent} <- [
          {"ssju00", "Committee on the Judiciary", "committee", nil},
          {"ssju01", "Subcommittee on the Constitution", "subcommittee", "ssju00"},
          {"ssfi00", "Committee on Finance", "committee", nil}
        ] do
      write!(%Records.Body{
        jurisdiction: "federal",
        external_id: id,
        name: name,
        classification: class,
        parent_external_id: parent,
        source: @src
      })
    end

    for {body, role} <- [{"ssju00", "chair"}, {"ssju01", "member"}, {"ssfi00", "member"}] do
      write!(%Records.Membership{
        jurisdiction: "federal",
        person: {"bioguide", "G000386"},
        body_external_id: body,
        role: role,
        source: @src
      })
    end
  end

  defp former! do
    write!(%Records.Person{
      identifiers: [{"bioguide", "F000001"}],
      name: "Pat Former",
      source: @src
    })

    for {start, finish} <- [{~D[2019-01-03], ~D[2021-01-03]}, {~D[2021-01-03], ~D[2023-01-03]}] do
      write!(%Records.Membership{
        jurisdiction: "federal",
        person: {"bioguide", "F000001"},
        body_external_id: "house",
        role: "member",
        party: "Democratic",
        district: "IA-2",
        start_date: start,
        end_date: finish,
        source: @src
      })
    end

    Legislature.get_person_by_identifier("bioguide", "F000001")
  end

  defp cosponsored_bills!(count) do
    for n <- 1..count do
      id = "119-s-#{100 + n}"

      write!(%Records.Bill{
        jurisdiction: "federal",
        session_identifier: "119",
        external_id: id,
        identifier: "S. #{100 + n}",
        classification: "bill",
        title: "#{ordinal(n)} bill title",
        from_body_external_id: "senate",
        introduced_on: Date.add(~D[2025-01-01], -n),
        source: @src
      })

      write!(%Records.Sponsorships{
        jurisdiction: "federal",
        bill_external_id: id,
        sponsorships: [
          %{
            person: {"bioguide", "E000295"},
            classification: "cosponsor",
            date: nil,
            withdrawn_on: nil
          }
        ],
        source: @src
      })
    end
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"

  test "a person's page shows who they are, their week, their bills and committees", %{
    conn: conn,
    grassley: p
  } do
    committees!()
    {:ok, view, html} = live(conn, ~p"/people/#{p.id}")
    assert html =~ "Chuck Grassley"
    assert html =~ "Senate · Republican · Iowa"
    assert html =~ "since Jan 2025"
    assert html =~ ">Chuck Grassley · Everyday Citizen</title>"
    assert has_element?(view, "#follow-rep")
    assert has_element?(view, "#week")
    assert html =~ "Bills they sponsored"
    assert html =~ "Bills they cosponsored"
    assert has_element?(view, "#cosponsored a[href=\"/bills/119-s-5\"]", "S. 5")
    assert html =~ "Judiciary"

    # committees first, each with its subcommittees under it, then by name
    names =
      view
      |> element("#committees")
      |> render()
      |> then(&Regex.scan(~r/(?:Subcommittee|Committee) on (?:the )?\w+/, &1))
      |> Enum.map(&hd/1)

    assert names == [
             "Committee on Finance",
             "Committee on the Judiciary",
             "Subcommittee on the Constitution"
           ]

    assert has_element?(view, "#committees li", "Chair")
  end

  test "a former member's page shows their last role and record", %{conn: conn} do
    former = former!()
    {:ok, _view, html} = live(conn, ~p"/people/#{former.id}")
    assert html =~ "Pat Former"
    assert html =~ "House of Representatives · Democratic · Iowa&#39;s 2nd district"
    assert html =~ "Served until Jan 2023"
    refute html =~ "since"
  end

  test "show more loads further cosponsored bills in place", %{conn: conn, ernst: e} do
    cosponsored_bills!(7)
    {:ok, view, html} = live(conn, ~p"/people/#{e.id}")
    assert html =~ "1st bill title"
    assert html =~ "5th bill title"
    refute html =~ "6th bill title"

    html = view |> element("button[phx-click=more_cosponsored]") |> render_click()
    assert html =~ "7th bill title"
    assert html =~ "1st bill title"
    refute has_element?(view, "button[phx-click=more_cosponsored]")
  end

  test "an unknown person is not found", %{conn: conn} do
    assert_raise EverydayCitizenWeb.NotFoundError, fn -> live(conn, ~p"/people/999999") end
    assert_raise EverydayCitizenWeb.NotFoundError, fn -> live(conn, ~p"/people/abc") end
  end

  test "the week switcher and filters stay on the person's page", %{conn: conn, ernst: e} do
    {:ok, view, _html} = live(conn, ~p"/people/#{e.id}?week=2026-01-19&filter=votes")
    assert render(view) =~ "Voted Nay"

    assert has_element?(
             view,
             ~s(#week a[aria-label="Previous week"][href="/people/#{e.id}?filter=votes&week=2026-01-12"])
           )
  end

  test "a crawler never starts a week summary on a person page", %{conn: conn, ernst: e} do
    conn = Plug.Conn.put_req_header(conn, "user-agent", "facebookexternalhit/1.1")

    {:ok, view, html} = live(conn, ~p"/people/#{e.id}?week=2026-01-19")
    refute has_element?(view, "#week-summary")
    refute html =~ "Writing a plain-English summary"
    assert [] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)
  end

  describe "queries" do
    test "get_person takes integer or string ids and rejects anything else", %{grassley: g} do
      assert Legislature.get_person(g.id).id == g.id
      assert Legislature.get_person("#{g.id}").id == g.id
      assert Legislature.get_person("#{g.id}x") == nil
      assert Legislature.get_person("abc") == nil
      assert Legislature.get_person("99999999999999999999") == nil
      assert Legislature.get_person("-1") == nil
    end

    test "sponsored_bills pages newest first and counts the total", %{ernst: e} do
      cosponsored_bills!(7)
      %{bills: first, total: 7} = Legislation.sponsored_bills(e.id, "cosponsor", limit: 5)

      assert Enum.map(first, & &1.bill.identifier) == [
               "S. 101",
               "S. 102",
               "S. 103",
               "S. 104",
               "S. 105"
             ]

      %{bills: rest} = Legislation.sponsored_bills(e.id, "cosponsor", limit: 10, offset: 5)
      assert Enum.map(rest, & &1.bill.identifier) == ["S. 106", "S. 107"]

      %{bills: [%{bill: %{identifier: "S. 5"}, latest: latest}], total: 1} =
        Legislation.sponsored_bills(e.id, "primary", [])

      assert latest.classification == "passed_chamber"
    end
  end
end
