defmodule EverydayCitizen.Ingest.OriginsEnqueueTest do
  # a bill's stored origins are redone only when its versions change
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.{Ingest, Legislation}
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Jobs.ComputeOrigins

  @src Records.SourceRef.new("https://x.test/v", "v")

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    %{bill: Legislation.get_bill("federal", "119-s-5")}
  end

  defp version(date, code \\ "ih"),
    do: %Records.BillVersion{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      code: code,
      classification: code,
      date: date,
      source: @src
    }

  defp text(sections),
    do: %Records.BillVersionText{
      jurisdiction: "federal",
      bill_external_id: "119-s-5",
      code: "ih",
      xml: "<bill/>",
      xml_schema: "uslm",
      plain_text: "Text.",
      sections: sections,
      sections_version: 2,
      source: @src
    }

  defp jobs, do: all_enqueued(worker: ComputeOrigins)

  defp clear, do: Repo.delete_all(Oban.Job)

  @sec [%{"kind" => "section", "enum" => "1.", "heading" => "Short title", "blocks" => []}]

  test "a new version or a new date queues the bill; the same version again doesn't", %{
    bill: bill
  } do
    {:ok, _} = Ingest.write(version(~D[2026-01-06]), nil)
    assert [%{args: %{"bill_id" => id}}] = jobs()
    assert id == bill.id

    clear()
    {:ok, _} = Ingest.write(version(~D[2026-01-06]), nil)
    assert jobs() == []

    {:ok, _} = Ingest.write(version(~D[2026-01-07]), nil)
    assert [_] = jobs()
  end

  test "new sections queue the bill; the same sections again don't" do
    {:ok, _} = Ingest.write(version(~D[2026-01-06]), nil)
    clear()

    {:ok, _} = Ingest.write(text(@sec), nil)
    assert [_] = jobs()

    clear()
    {:ok, _} = Ingest.write(text(@sec), nil)
    assert jobs() == []
  end

  test "put_sections queues the bill only when the sections differ", %{bill: bill} do
    {:ok, _} = Ingest.write(version(~D[2026-01-06]), nil)
    clear()
    v = Legislation.get_version(bill, "ih")

    :ok = Legislation.put_sections(v.id, @sec, 2)
    assert [_] = jobs()

    clear()
    :ok = Legislation.put_sections(v.id, @sec, 3)
    assert jobs() == []
  end

  test "many versions of one bill written together queue it once" do
    for code <- ~w(ih rh eh), do: {:ok, _} = Ingest.write(version(~D[2026-01-06], code), nil)
    assert [_] = jobs()
  end
end
