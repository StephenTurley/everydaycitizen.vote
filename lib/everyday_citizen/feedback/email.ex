defmodule EverydayCitizen.Feedback.Email do
  @moduledoc "The email to the admin about one feedback report."
  import Swoosh.Email

  alias EverydayCitizen.Feedback.Report

  @labels %{
    "section" => "section summary",
    "bill" => "bill summary",
    "rep_week" => "week summary",
    "site" => "site"
  }

  @spec build(Report.t(), String.t()) :: Swoosh.Email.t()
  def build(%Report{} = report, to) do
    new()
    |> to(to)
    |> from(Application.fetch_env!(:everyday_citizen, :mail_from))
    |> subject("Feedback: #{report.reason} (#{@labels[report.kind]})")
    |> text_body(body(report))
  end

  defp body(report) do
    [
      "Reason: #{report.reason}",
      "Note: #{report.note || "(none)"}",
      report.page && "Page: #{EverydayCitizenWeb.Endpoint.url()}#{report.page}",
      "From: #{if report.user, do: report.user.email, else: "not signed in"}",
      report.subject && "Summary: #{report.subject}, prompt #{report.prompt_version}",
      report.summary && "\nWhat they saw:\n#{report.summary}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end
end
