defmodule EverydayCitizen.Jobs.ComputeOriginsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  import EverydayCitizen.HistoryFixtures

  alias EverydayCitizen.{BillHistory, Legislation}
  alias EverydayCitizen.Jobs.ComputeOrigins
  alias EverydayCitizen.Legislation.BillVersion

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    %{bill: three_versions!()}
  end

  defp stored(bill, code),
    do: bill |> Legislation.get_version(code) |> BillHistory.stored_origins()

  test "stores each version's origins, as worked out from all its versions", %{bill: bill} do
    Repo.update_all(from(v in BillVersion, where: v.bill_id == ^bill.id), set: [origins: nil])
    assert stored(bill, "eh") == nil
    assert :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})

    for code <- ~w(ih rh eh), do: assert(stored(bill, code) == BillHistory.origins(bill, code))
    assert %{2 => %{status: :added, added_in: "eh", changed_in: []}} = stored(bill, "eh")
  end

  test "a bill with one version stores nothing to compare", %{bill: bill} do
    Repo.delete_all(from v in BillVersion, where: v.bill_id == ^bill.id and v.code != "ih")
    assert :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})
    assert stored(bill, "ih") == %{}
  end

  test "running it again changes nothing", %{bill: bill} do
    :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})
    first = stored(bill, "eh")
    :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})
    assert stored(bill, "eh") == first
  end

  test "a bill that no longer exists is skipped" do
    assert :ok = perform_job(ComputeOrigins, %{"bill_id" => -1})
  end

  describe "fill/0" do
    test "a bill with several versions is queued once", %{bill: bill} do
      Repo.update_all(BillVersion, set: [origins: nil])
      Repo.delete_all(Oban.Job)

      assert %{one_version: _, queued: 1} = ComputeOrigins.fill()
      assert [%{args: %{"bill_id" => id}}] = all_enqueued(worker: ComputeOrigins)
      assert id == bill.id

      # run again with the job still waiting: nothing new
      assert %{queued: 0} = ComputeOrigins.fill()
    end

    test "a bill with one version stores %{} directly", %{bill: bill} do
      Repo.delete_all(from v in BillVersion, where: v.bill_id == ^bill.id and v.code != "ih")
      Repo.update_all(BillVersion, set: [origins: nil])

      assert %{one_version: 1, queued: 0} = ComputeOrigins.fill()
      assert stored(bill, "ih") == %{}
    end
  end
end
