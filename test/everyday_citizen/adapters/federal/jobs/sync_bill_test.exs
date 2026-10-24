defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncBillTest do
  use EverydayCitizen.DataCase, async: true
  import Ecto.Query
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.{SyncBill, SyncBills, SyncBillText, SyncCongress}
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records.{Person, SourceRef}
  alias EverydayCitizen.Legislation.{Bill, BillAction, BillVersion, Sponsorship}
  alias EverydayCitizen.Repo

  @dir "test/support/fixtures/federal/congress_gov"

  defp read(path), do: File.read!("#{@dir}/#{path}")

  @fixtures %{
    "/v3/congress/119" => "congress_119.json",
    "/v3/bill/119/hr/22" => "bill_119_hr_22/bill.json",
    "/v3/bill/119/hr/22/actions" => "bill_119_hr_22/actions.json",
    "/v3/bill/119/hr/22/cosponsors" => "bill_119_hr_22/cosponsors.json",
    "/v3/bill/119/hr/22/subjects" => "bill_119_hr_22/subjects.json",
    "/v3/bill/119/hr/22/text" => "bill_119_hr_22/text.json",
    "/v3/bill/119/hr/22/summaries" => "bill_119_hr_22/summaries.json"
  }

  defp stub(failing \\ %{}) do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      case Map.fetch(failing, conn.request_path) do
        {:ok, status} -> Plug.Conn.send_resp(conn, status, "{}")
        :error -> Plug.Conn.send_resp(conn, 200, body(conn))
      end
    end)
  end

  defp body(%{request_path: "/v3/bill/119"} = conn), do: list_page(conn)
  defp body(%{request_path: path}), do: read(Map.fetch!(@fixtures, path))

  # Page 1 is the captured response (it links to offset=2); offset=2 is past the end.
  defp list_page(%{query_string: query}) do
    send(self(), {:list_query, query})

    if query =~ "offset=2",
      do: ~s({"bills": [], "pagination": {"count": 2}}),
      else: read("bill_list_page.json")
  end

  setup do
    stub()
    assert :ok = perform_job(SyncCongress, %{"congress" => 119})

    {:ok, run} = EverydayCitizen.Provenance.start_run("federal", "test")
    source = SourceRef.new("https://example.test/people", "p")
    cosponsors = "bill_119_hr_22/cosponsors.json" |> read() |> JSON.decode!()

    for id <- ["R000614" | Enum.map(cosponsors["cosponsors"], & &1["bioguideId"])] do
      {:ok, _} =
        Ingest.write(%Person{identifiers: [{"bioguide", id}], name: id, source: source}, run.id)
    end

    succeeded!("sync_members")
    :ok
  end

  defp succeeded!(job) do
    {:ok, run} = EverydayCitizen.Provenance.start_run("federal", job)
    {:ok, run} = EverydayCitizen.Provenance.finish_run(run, :succeeded, %{}, nil)
    run
  end

  @args %{"congress" => 119, "type" => "hr", "number" => "22", "run_id" => nil}

  defp counts do
    %{
      bills: Repo.aggregate(Bill, :count),
      actions: Repo.aggregate(BillAction, :count),
      sponsorships: Repo.aggregate(Sponsorship, :count),
      versions: Repo.aggregate(BillVersion, :count)
    }
  end

  defp run_id do
    {:ok, run} = EverydayCitizen.Provenance.start_run("federal", "sync_bills")
    run.id
  end

  test "SyncBill writes bill, actions, sponsors, versions; idempotent" do
    args = %{@args | "run_id" => run_id()}
    assert :ok = perform_job(SyncBill, args)

    assert counts() == %{bills: 1, actions: 19, sponsorships: 6, versions: 2}
    bill = Repo.get_by!(Bill, external_id: "119-hr-22")
    assert length(bill.subjects) == 11

    source_url = fn id -> Repo.preload(Repo.get!(BillAction, id), :source).source.url end
    action = Repo.one!(from a in BillAction, where: a.position == 0)
    assert source_url.(action.id) =~ "/bill/119/hr/22/actions"

    summary = EverydayCitizen.Legislation.latest_summary(bill) |> Repo.preload(:source)
    assert summary.author == "Congressional Research Service"
    assert summary.source.url =~ "/bill/119/hr/22/summaries"

    assert :ok = perform_job(SyncBill, args)
    assert counts() == %{bills: 1, actions: 19, sponsorships: 6, versions: 2}
  end

  test "enqueues text fetches for versions without text" do
    assert :ok = perform_job(SyncBill, %{@args | "run_id" => run_id()})

    assert_enqueued(
      worker: SyncBillText,
      args: %{"bill_external_id" => "119-hr-22", "code" => "eh"}
    )

    assert_enqueued(
      worker: SyncBillText,
      args: %{"bill_external_id" => "119-hr-22", "code" => "ih"}
    )
  end

  test "a failed cosponsors fetch returns an error and keeps stored sponsorships" do
    id = run_id()
    assert :ok = perform_job(SyncBill, %{@args | "run_id" => id})
    before = counts()

    stub(%{"/v3/bill/119/hr/22/cosponsors" => 500})
    assert {:error, _} = perform_job(SyncBill, %{@args | "run_id" => id})
    assert counts() == before
  end

  test "a failed actions fetch returns an error and keeps stored actions" do
    id = run_id()
    assert :ok = perform_job(SyncBill, %{@args | "run_id" => id})
    before = counts()

    stub(%{"/v3/bill/119/hr/22/actions" => 500})
    assert {:error, _} = perform_job(SyncBill, %{@args | "run_id" => id})
    assert counts() == before
  end

  # The first run loads from bulk data (SyncBillsBulkTest); these cover later runs.
  test "SyncBills enqueues one SyncBill per listed bill and records the run" do
    succeeded!("sync_bills")
    assert :ok = perform_job(SyncBills, %{"congress" => 119})

    assert [_, _] = all_enqueued(worker: SyncBill)

    assert_enqueued(
      worker: SyncBill,
      args: %{"congress" => 119, "type" => "hr", "number" => "10389"}
    )

    assert_enqueued(
      worker: SyncBill,
      args: %{"congress" => 119, "type" => "s", "number" => "5677"}
    )

    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "sync_bills")

    # unique on congress/type/number: a second pass adds no jobs
    assert :ok = perform_job(SyncBills, %{"congress" => 119})
    assert [_, _] = all_enqueued(worker: SyncBill)
  end

  test "SyncBills lists from 2 days before the previous run's start" do
    succeeded!("sync_bills")
    |> Ecto.Changeset.change(started_at: ~U[2026-10-01 12:30:00.000000Z])
    |> Repo.update!()

    assert :ok = perform_job(SyncBills, %{"congress" => 119})
    assert_received {:list_query, query}
    assert URI.decode_query(query)["fromDateTime"] == "2026-09-29T12:30:00Z"
  end
end
