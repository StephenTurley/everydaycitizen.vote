defmodule EverydayCitizen.Ingest.Writer.PostalDistricts do
  @moduledoc """
  Replaces a jurisdiction's whole postal-code-to-district table with a new file's
  rows, in one transaction, inserted in batches.
  """
  import Ecto.Query

  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Ingest.Writer.Support
  alias EverydayCitizen.Legislature.PostalDistrict
  alias EverydayCitizen.Repo

  @spec write(Records.PostalDistricts.t(), integer() | nil) :: {:ok, map()} | {:error, term()}
  def write(%Records.PostalDistricts{} = r, run_id) do
    Support.transact(r, run_id, fn source_id ->
      with {:ok, j} <- Support.jurisdiction(r.jurisdiction), do: replace(j, r.rows, source_id)
    end)
  end

  defp replace(jurisdiction, rows, source_id) do
    Repo.delete_all(from p in PostalDistrict, where: p.jurisdiction_id == ^jurisdiction.id)
    now = DateTime.utc_now()

    extra = %{
      jurisdiction_id: jurisdiction.id,
      source_id: source_id,
      inserted_at: now,
      updated_at: now
    }

    rows
    |> Enum.map(&Map.merge(&1, extra))
    |> Enum.chunk_every(2000)
    |> Enum.each(&Repo.insert_all(PostalDistrict, &1))

    {:ok, %{written: length(rows)}}
  end
end
