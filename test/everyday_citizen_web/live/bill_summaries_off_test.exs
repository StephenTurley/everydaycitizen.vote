defmodule EverydayCitizenWeb.BillSummariesOffTest do
  # not async: turns summaries off in the application config
  use EverydayCitizenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    key = Application.get_env(:everyday_citizen, :anthropic_api_key)
    Application.put_env(:everyday_citizen, :anthropic_api_key, nil)
    on_exit(fn -> Application.put_env(:everyday_citizen, :anthropic_api_key, key) end)
    :ok
  end

  test "with summaries off, an opened section shows only its text", %{conn: conn} do
    bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")

    {:ok, _} =
      EverydayCitizen.Ingest.write(
        %EverydayCitizen.Ingest.Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: "119-s-5",
          code: "is",
          source: EverydayCitizen.Ingest.Records.SourceRef.new("https://x.test/v", "v")
        },
        nil
      )

    v = EverydayCitizen.Legislation.get_version(bill, "is")

    :ok =
      EverydayCitizen.Legislation.put_sections(
        v.id,
        [
          %{
            "kind" => "section",
            "enum" => "1.",
            "heading" => "A",
            "blocks" => [%{"level" => 0, "enum" => nil, "heading" => nil, "text" => "Text."}]
          }
        ],
        2
      )

    {:ok, view, _html} = live(conn, ~p"/bills/119-s-5?section=0")
    assert has_element?(view, ".section-text", "Text.")
    refute has_element?(view, "#summary-0")
  end
end
