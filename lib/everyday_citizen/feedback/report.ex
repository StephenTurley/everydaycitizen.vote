defmodule EverydayCitizen.Feedback.Report do
  @moduledoc """
  A reader's report about an AI summary (kind `section`, `bill` or `rep_week`,
  with the summary's subject, prompt version and text as shown) or about the
  site (`site`): a reason, an optional note, the page, and the account when
  signed in. No address or IP is kept.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(section bill rep_week site)
  @reasons ~w(inaccurate unclear missing one_sided other)

  schema "feedback_reports" do
    field :kind, :string
    field :subject, :string
    field :prompt_version, :string
    field :summary, :string
    field :page, :string
    field :reason, :string
    field :note, :string
    belongs_to :user, EverydayCitizen.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def reasons, do: @reasons

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:kind, :subject, :prompt_version, :summary, :page, :reason, :note])
    |> validate_required([:kind, :reason])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:reason, @reasons)
    |> validate_length(:note, max: 1_000)
    |> validate_length(:page, max: 255)
  end
end
