defmodule EverydayCitizen.Repo.Migrations.AddBillVersionsOrigins do
  @moduledoc """
  Where each section of a version came from, worked out when the bill's
  versions change (`Jobs.ComputeOrigins`) rather than on every page view.
  NULL until worked out.
  """
  use Ecto.Migration

  def change do
    alter table(:bill_versions), do: add(:origins, :map)
  end
end
