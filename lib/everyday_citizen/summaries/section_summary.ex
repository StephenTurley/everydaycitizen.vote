defmodule EverydayCitizen.Summaries.SectionSummary do
  @moduledoc """
  A plain-English summary of one section of a bill version, with what it was
  written from: the hash of the section's text, the model and the prompt version.
  """
  use Ecto.Schema

  schema "section_summaries" do
    belongs_to :bill_version, EverydayCitizen.Legislation.BillVersion
    field :section_index, :integer
    field :prompt_version, :string
    field :model, :string
    field :source_hash, :binary
    field :summary, :string
    field :input_tokens, :integer
    field :output_tokens, :integer

    timestamps(type: :utc_datetime)
  end
end
