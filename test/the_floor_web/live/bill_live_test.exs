defmodule TheFloorWeb.BillLiveTest do
  use TheFloorWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TheFloor.Ingest
  alias TheFloor.Ingest.Records

  @src Records.SourceRef.new("https://www.congress.gov/x", "x")

  setup %{conn: conn} do
    people = TheFloor.FloorFixtures.iowa!()
    {:ok, Map.put(people, :conn, init_test_session(conn, %{district: "IA-1"}))}
  end

  defp add_versions! do
    for {code, date, heading} <- [
          {"is", ~D[2026-01-06], "Short title"},
          {"es", ~D[2026-01-20], "Short title as passed"}
        ] do
      {:ok, _} =
        Ingest.write(
          %Records.BillVersion{
            jurisdiction: "federal",
            bill_external_id: "119-s-5",
            code: code,
            classification: code,
            date: date,
            source: @src
          },
          nil
        )

      bill = TheFloor.Legislation.get_bill("federal", "119-s-5")
      v = TheFloor.Legislation.get_version(bill, code)

      :ok =
        TheFloor.Legislation.put_sections(v.id, [
          %{
            "kind" => "section",
            "enum" => "1.",
            "heading" => heading,
            "blocks" => [
              %{
                "level" => 0,
                "enum" => nil,
                "heading" => nil,
                "text" => "This Act may be cited as #{code}."
              }
            ]
          },
          %{
            "kind" => "section",
            "enum" => "2.",
            "heading" => "Detention",
            "blocks" => [
              %{"level" => 0, "enum" => "(a)", "heading" => "In general", "text" => "Text."},
              %{"level" => 2, "enum" => "(A)", "heading" => nil, "text" => "Deeper."}
            ]
          }
        ])
    end
  end

  test "the bill, where it stands, and how your reps were involved", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5")

    assert html =~ "Laken Riley Act"
    assert html =~ "S. 5"
    assert html =~ ~s(aria-current="step")
    assert html =~ "Joni Ernst"
    assert html =~ "Sponsor"
    assert html =~ "No vote yet"
    assert html =~ "1 cosponsor"
    assert html =~ ~s(href="https://www.congress.gov/x")
  end

  test "missing summary and text each say so in one line", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5")
    assert html =~ "No official summary yet."
    assert html =~ "No text published yet."
  end

  test "the newest version is shown; picking another changes the sections", %{conn: conn} do
    add_versions!()
    {:ok, view, html} = live(conn, ~p"/bills/119-s-5")
    assert html =~ "Short title as passed"

    html = view |> element("#version-form") |> render_change(%{"version" => "is"})
    assert html =~ "Short title"
    refute html =~ "Short title as passed"
  end

  test "opening a section shows its text, indented by level", %{conn: conn} do
    add_versions!()
    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5?section=1")
    assert html =~ "Deeper."
    assert html =~ ~s(data-level="2")
  end

  test "votes on the bill are listed", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5")
    assert html =~ "Passed, 64–35" or html =~ "Bill Passed, 64–35"
  end

  test "an unknown bill is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/bills/119-hr-99999") end
  end

  test "sections open by position, so repeated or missing numbers work", %{conn: conn} do
    {:ok, _} =
      Ingest.write(
        %Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: "119-s-5",
          code: "is",
          date: ~D[2026-01-06],
          source: @src
        },
        nil
      )

    v =
      TheFloor.Legislation.get_version(TheFloor.Legislation.get_bill("federal", "119-s-5"), "is")

    :ok =
      TheFloor.Legislation.put_sections(v.id, [
        %{
          "kind" => "section",
          "enum" => "101.",
          "heading" => "A",
          "blocks" => [
            %{"level" => 0, "enum" => nil, "heading" => nil, "text" => "First division text."}
          ]
        },
        %{
          "kind" => "section",
          "enum" => "101.",
          "heading" => "B",
          "blocks" => [
            %{"level" => 0, "enum" => nil, "heading" => nil, "text" => "Second division text."}
          ]
        },
        %{
          "kind" => "section",
          "enum" => nil,
          "heading" => "Unnumbered",
          "blocks" => [%{"level" => 0, "enum" => nil, "heading" => nil, "text" => "Loose text."}]
        }
      ])

    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5?section=1")
    assert html =~ "Second division text."
    refute html =~ "First division text."
    refute html =~ "Loose text."
  end
end
