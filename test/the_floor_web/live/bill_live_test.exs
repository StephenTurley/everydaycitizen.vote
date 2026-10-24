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
        TheFloor.Legislation.put_sections(
          v.id,
          [
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
          ],
          2
        )
    end
  end

  test "law the bill quotes shows as its own labeled block", %{conn: conn} do
    {:ok, _} =
      Ingest.write(
        %Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: "119-s-5",
          code: "is",
          classification: "is",
          date: ~D[2026-01-06],
          source: @src
        },
        nil
      )

    bill = TheFloor.Legislation.get_bill("federal", "119-s-5")

    :ok =
      TheFloor.Legislation.put_sections(
        TheFloor.Legislation.get_version(bill, "is").id,
        [
          %{
            "kind" => "section",
            "enum" => "1.",
            "heading" => "Amendment",
            "blocks" => [
              %{
                "level" => 0,
                "enum" => nil,
                "heading" => nil,
                "text" => "Section 5 is amended by adding:"
              },
              %{
                "level" => 0,
                "quote" => [
                  %{"level" => 0, "enum" => "6.", "heading" => "New", "text" => "Inserted text."}
                ]
              }
            ]
          }
        ],
        2
      )

    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?section=0")

    assert has_element?(view, "figure figcaption", "Text this section adds to the law")
    assert has_element?(view, "figure", "6.")
    assert has_element?(view, "figure", "Inserted text.")
    assert has_element?(view, ".section-text", "Section 5 is amended by adding:")
    refute has_element?(view, "figure", "amended by adding")
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

  test "Expand all opens every section; Collapse all closes them", %{conn: conn} do
    add_versions!()
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")
    assert has_element?(view, "a", "Expand all")
    refute has_element?(view, ".section-text")

    {:ok, view, html} = live(conn, ~p"/bills/119-s-5?version=es&section=all")
    assert html =~ "This Act may be cited as es."
    assert html =~ "Deeper."
    assert has_element?(view, "a", "Collapse all")
  end

  test "a section that is not a number opens nothing", %{conn: conn} do
    add_versions!()
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?section=nope")
    refute has_element?(view, ".section-text")
  end

  test "the contents list links every section and marks the open one", %{conn: conn} do
    add_versions!()
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=es&section=1")

    assert has_element?(
             view,
             ~s(nav[aria-label="Sections"] a[href*="section=0"][href*="version=es"])
           )

    assert has_element?(
             view,
             ~s(nav[aria-label="Sections"] a[href*="section=1"][aria-current="location"])
           )

    refute has_element?(view, ~s(nav[aria-label="Sections"] a[href*="section=0"][aria-current]))
    assert has_element?(view, "#section-1")
  end

  test "a step passed over shows Skipped", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5")
    assert html =~ "Skipped"
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
      TheFloor.Legislation.put_sections(
        v.id,
        [
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
            "blocks" => [
              %{"level" => 0, "enum" => nil, "heading" => nil, "text" => "Loose text."}
            ]
          }
        ],
        2
      )

    {:ok, _view, html} = live(conn, ~p"/bills/119-s-5?section=1")
    assert html =~ "Second division text."
    refute html =~ "First division text."
    refute html =~ "Loose text."
  end
end
