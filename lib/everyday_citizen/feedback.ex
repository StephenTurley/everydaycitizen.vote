defmodule EverydayCitizen.Feedback do
  @moduledoc """
  Reports from readers: about an AI summary ("Report a problem" under each one)
  or the site ("Send feedback"). Each is stored and emailed to the admin
  address (`:feedback_to`, from `FEEDBACK_EMAIL`), one email per report.
  """
  alias Ecto.Multi
  alias EverydayCitizen.Accounts.User
  alias EverydayCitizen.Feedback.Report
  alias EverydayCitizen.Jobs.SendFeedbackEmail
  alias EverydayCitizen.Repo

  @spec submit(map(), User.t() | nil) :: {:ok, Report.t()} | {:error, Ecto.Changeset.t()}
  def submit(attrs, user) do
    changeset =
      %Report{user_id: user && user.id}
      |> Report.changeset(attrs)

    Multi.new()
    |> Multi.insert(:report, changeset)
    |> Oban.insert(:email, fn %{report: r} -> SendFeedbackEmail.new(%{report_id: r.id}) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{report: report}} -> {:ok, report}
      {:error, :report, changeset, _} -> {:error, changeset}
    end
  end

  @spec get(integer()) :: Report.t() | nil
  def get(id), do: Report |> Repo.get(id) |> Repo.preload(:user)
end
