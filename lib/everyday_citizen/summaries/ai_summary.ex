defmodule EverydayCitizen.Summaries.AiSummary do
  @moduledoc """
  A plain-English summary of a whole bill (`kind` "bill", subject
  `"bill:<id>:<version code>"`) or of a rep's week (`kind` "rep_week", subject
  `"rep_week:<person id>:<monday>"`), with the hash of the input it was written
  from, the model and the prompt version.
  """
  use Ecto.Schema

  schema "ai_summaries" do
    field :kind, :string
    field :subject, :string
    field :prompt_version, :string
    field :model, :string
    field :source_hash, :binary
    field :summary, :string
    field :input_tokens, :integer
    field :output_tokens, :integer

    timestamps(type: :utc_datetime)
  end
end
