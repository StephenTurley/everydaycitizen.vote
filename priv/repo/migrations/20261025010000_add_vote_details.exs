defmodule EverydayCitizen.Repo.Migrations.AddVoteDetails do
  use Ecto.Migration

  def change do
    alter table(:votes) do
      # what was voted on, in the source's words (a nominee, an amendment's purpose)
      add :description, :text
      # the source's reference for it and its official page, when it is not the bill
      add :subject_ref, :string
      add :subject_url, :string
    end
  end
end
