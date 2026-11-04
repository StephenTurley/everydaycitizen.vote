defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncBillsTest do
  # changes the :federal config's date
  use EverydayCitizen.DataCase, async: false
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Job
  alias EverydayCitizen.Adapters.Federal.Jobs.{SyncBill, SyncBills, SyncCongress}

  @moduletag :capture_log

  @congress_119 "test/support/fixtures/federal/congress_gov/congress_119.json"

  # Serves congresses 119 and 120 and a one-bill listing for any congress,
  # reporting each listing's path and parameters.
  defp stub do
    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      case conn.request_path do
        "/v3/congress/" <> number ->
          body = @congress_119 |> File.read!() |> String.replace("119", number)
          Plug.Conn.send_resp(conn, 200, body)

        "/v3/bill/" <> number ->
          send(self(), {:listing, number, Plug.Conn.fetch_query_params(conn).query_params})

          Plug.Conn.send_resp(
            conn,
            200,
            ~s({"bills": [{"type": "HR", "number": 1}], "pagination": {"count": 1}})
          )
      end
    end)
  end

  defp on(date) do
    previous = Application.fetch_env!(:everyday_citizen, :federal)
    Application.put_env(:everyday_citizen, :federal, Keyword.put(previous, :today, date))
    on_exit(fn -> Application.put_env(:everyday_citizen, :federal, previous) end)
  end

  setup do
    stub()
    assert :ok = perform_job(SyncCongress, %{"congress" => 119})
    assert :ok = perform_job(SyncCongress, %{"congress" => 120})
    # a members sync and an earlier bill sync have succeeded (the incremental path)
    :ok = Job.run("sync_members", fn _run_id, _cursor -> {:ok, %{}} end)
    :ok = Job.run("sync_bills", fn _run_id, _cursor -> {:ok, %{}} end)
    :ok
  end

  test "lists the previous congress's bills too in the first 30 days" do
    on(~D[2027-01-10])

    assert :ok = perform_job(SyncBills, %{})

    assert_received {:listing, "120", %{"fromDateTime" => from}}
    assert_received {:listing, "119", %{"fromDateTime" => ^from}}
    assert_enqueued(worker: SyncBill, args: %{"congress" => 120, "type" => "hr", "number" => "1"})
    assert_enqueued(worker: SyncBill, args: %{"congress" => 119, "type" => "hr", "number" => "1"})
  end

  test "lists only the sitting congress after 30 days" do
    on(~D[2027-02-02])

    assert :ok = perform_job(SyncBills, %{})

    assert_received {:listing, "120", _}
    refute_received {:listing, "119", _}
  end

  test "an explicit congress argument lists only that congress" do
    on(~D[2027-01-10])

    assert :ok = perform_job(SyncBills, %{"congress" => 119})

    assert_received {:listing, "119", _}
    refute_received {:listing, "120", _}
  end
end
