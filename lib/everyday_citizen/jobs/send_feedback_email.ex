defmodule EverydayCitizen.Jobs.SendFeedbackEmail do
  @moduledoc """
  Emails one feedback report to the admin address (`:feedback_to`); with none
  configured it sends nothing (the report is still stored).
  """
  use Oban.Worker, queue: :mail, max_attempts: 5

  alias EverydayCitizen.{Feedback, Mailer}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"report_id" => id}}) do
    with to when is_binary(to) <- Application.get_env(:everyday_citizen, :feedback_to),
         %{} = report <- Feedback.get(id),
         {:ok, _} <-
           Mailer.deliver(
             Feedback.Email.build(report, to),
             Application.get_env(:everyday_citizen, :mailer_overrides, [])
           ) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _nothing_to_send -> :ok
    end
  end
end
