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

  test "a bill with one version is left alone: there is nothing to compare", %{bill: bill} do
    Repo.delete_all(from v in BillVersion, where: v.bill_id == ^bill.id and v.code != "ih")
    Repo.update_all(from(v in BillVersion, where: v.bill_id == ^bill.id), set: [origins: nil])
    assert :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})
    assert Repo.one(from v in BillVersion, where: v.bill_id == ^bill.id, select: v.origins) == nil
  end

  test "origins stored by an older way of working them out count as not worked out", %{
    bill: bill
  } do
    :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})
    v = EverydayCitizen.Legislation.get_version(bill, "eh")
    assert BillHistory.stored_origins(v)
    assert BillHistory.stored_origins(%{v | origins: Map.put(v.origins, "v", 0)}) == nil
    assert BillHistory.stored_origins(%{origins: %{"0" => %{"status" => "added"}}}) == nil

    Repo.update_all(from(x in BillVersion, where: x.id == ^v.id),
      set: [origins: Map.put(v.origins, "v", 0)]
    )

    Repo.delete_all(Oban.Job)
    assert %{queued: 1} = ComputeOrigins.fill()
  end

  test "a status this code doesn't know counts as not worked out", %{bill: bill} do
    :ok = perform_job(ComputeOrigins, %{"bill_id" => bill.id})
    v = EverydayCitizen.Legislation.get_version(bill, "eh")
    odd = put_in(v.origins, ["sections", "0", "status"], "moved")
    assert BillHistory.stored_origins(%{v | origins: odd}) == nil
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
    test "a bill with several versions is queued once; one-version bills aren't touched", %{
      bill: bill
    } do
      Repo.update_all(BillVersion, set: [origins: nil])
      Repo.delete_all(Oban.Job)

      assert %{queued: 1} = ComputeOrigins.fill()
      assert [%{args: %{"bill_id" => id}}] = all_enqueued(worker: ComputeOrigins)
      assert id == bill.id

      # run again with the job still waiting: nothing new
      assert %{queued: 0} = ComputeOrigins.fill()
    end
  end
end
