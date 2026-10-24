defmodule EverydayCitizen.Ingest.AtomicallyTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislature.Jurisdiction

  defp jurisdiction do
    %Records.Jurisdiction{
      key: "federal",
      name: "Federal",
      classification: "federal",
      source: Records.SourceRef.new("https://x.test/a", "a")
    }
  end

  test "writes inside it are kept when it returns ok" do
    assert {:ok, :done} =
             Ingest.atomically(fn ->
               {:ok, _} = Ingest.write(jurisdiction(), nil)
               {:ok, :done}
             end)

    assert Repo.aggregate(Jurisdiction, :count) == 1
  end

  test "an error undoes every write inside it" do
    assert {:error, :later_part_failed} =
             Ingest.atomically(fn ->
               {:ok, _} = Ingest.write(jurisdiction(), nil)
               {:error, :later_part_failed}
             end)

    assert Repo.aggregate(Jurisdiction, :count) == 0
  end
end
