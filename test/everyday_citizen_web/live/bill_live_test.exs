defmodule EverydayCitizenWeb.BillLiveTest do
  use EverydayCitizenWeb.ConnCase, async: true

  use Oban.Testing, repo: EverydayCitizen.Repo

  import Phoenix.LiveViewTest
  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  @src Records.SourceRef.new("https://www.congress.gov/x", "x")

  setup %{conn: conn} do
    people = EverydayCitizen.FloorFixtures.iowa!()
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

      bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")
      v = EverydayCitizen.Legislation.get_version(bill, code)

      :ok =
        EverydayCitizen.Legislation.put_sections(
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

    bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")

    :ok =
      EverydayCitizen.Legislation.put_sections(
        EverydayCitizen.Legislation.get_version(bill, "is").id,
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

  test "the bill links its official page, else its source record", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")
    assert has_element?(view, ~s(a[href="https://www.congress.gov/x"]), "Official page")

    EverydayCitizen.Repo.update_all(EverydayCitizen.Legislation.Bill,
      set: [web_url: "https://official.test/s5"]
    )

    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")
    assert has_element?(view, ~s(a[href="https://official.test/s5"]), "Official page")
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
    # a live patch (no full page load), with an href for before the socket connects
    assert has_element?(
             view,
             ~s(nav[aria-label="Sections"] a[data-phx-link="patch"][href*="section=0"])
           )
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
      EverydayCitizen.Legislation.get_version(
        EverydayCitizen.Legislation.get_bill("federal", "119-s-5"),
        "is"
      )

    :ok =
      EverydayCitizen.Legislation.put_sections(
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

  describe "following the bill" do
    test "signed out, Follow leads to sign-in and back to this bill", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")

      assert has_element?(
               view,
               ~s(a[href="/users/sign-in-to?to=%2Fbills%2F119-s-5"]),
               "Follow this bill"
             )
    end

    test "signed in, Follow toggles and is remembered", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")

      view |> element("#follow-bill") |> render_click()
      assert has_element?(view, ~s(#follow-bill[aria-pressed="true"]), "Following")

      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5")
      assert has_element?(view, ~s(#follow-bill[aria-pressed="true"]))

      view |> element("#follow-bill") |> render_click()
      assert has_element?(view, ~s(#follow-bill[aria-pressed="false"]), "Follow this bill")
    end

    test "with the daily email off, following says so", %{conn: conn} do
      user = user_fixture()
      EverydayCitizen.Repo.update!(Ecto.Changeset.change(user, digest_enabled: false))
      {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/bills/119-s-5")

      html = view |> element("#follow-bill") |> render_click()
      assert html =~ "Your daily email is off"
      assert has_element?(view, ~s(a[href="/users/settings"]))
    end
  end

  describe "plain-English summaries" do
    setup do
      add_versions!()
      bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")
      version = EverydayCitizen.Legislation.get_version(bill, "es")
      section = Enum.at(EverydayCitizen.BillPage.sections(bill, "es"), 1)
      %{version: version, text: EverydayCitizen.Summaries.section_text(section)}
    end

    defp cache!(version, text, summary) do
      {:ok, _} =
        EverydayCitizen.Summaries.put(version.id, 1, text, %{
          summary: summary,
          model: "claude-haiku-5-5"
        })
    end

    test "an opened section shows its cached summary above the text, labeled as AI-written", %{
      conn: conn,
      version: v,
      text: text
    } do
      cache!(v, text, "This section is about detention.")
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=es&section=1")

      assert has_element?(view, "#summary-1", "This section is about detention.")
      assert has_element?(view, "#summary-1", "Written by AI")

      assert has_element?(
               view,
               ~s(#summary-1 a[href="https://github.com/StephenTurley/everydaycitizen.vote/blob/main/priv/prompts/section_summary.v1.md"])
             )

      assert render(view) =~ ~r/id="summary-1".*Deeper\./s
    end

    test "an uncached section shows it is being written, then the summary when it lands", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=es&section=1")

      assert has_element?(view, "#summary-1", "Writing a plain-English summary")
      assert [_job] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSection)

      send(view.pid, {:section_summary, 1, {:ok, "Now it is explained."}})
      assert has_element?(view, "#summary-1", "Now it is explained.")
    end

    test "a summary that couldn't be written says so", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=es&section=1")
      send(view.pid, {:section_summary, 1, {:error, :unavailable}})
      assert has_element?(view, "#summary-1", "A summary isn't available right now.")
    end

    test "Expand all shows cached summaries but asks for no new ones", %{
      conn: conn,
      version: v,
      text: text
    } do
      cache!(v, text, "Cached already.")
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=es&section=all")

      assert has_element?(view, "#summary-1", "Cached already.")
      refute has_element?(view, "#summary-0")
      assert [] = all_enqueued(worker: EverydayCitizen.Jobs.SummarizeSection)
    end

    test "summary text is shown as text, never as HTML", %{conn: conn, version: v, text: text} do
      cache!(v, text, "<script>alert(1)</script> and more")
      {:ok, _view, html} = live(conn, ~p"/bills/119-s-5?version=es&section=1")

      assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
      refute html =~ "<script>alert(1)</script>"
    end

    test "a summary in short points shows as a list", %{conn: conn, version: v, text: text} do
      cache!(v, text, "- First point.\n- Second point.")
      {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?version=es&section=1")
      assert has_element?(view, "#summary-1 li", "Second point.")
    end
  end
end
