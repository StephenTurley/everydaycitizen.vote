defmodule EverydayCitizen.HistoryFixtures do
  @moduledoc """
  Three versions of the fixture bill 119-s-5 shaped like H.R. 7008: Sec. 1
  unchanged, Sec. 2's definition rewritten in the second version, and Sec. 3
  (photo identification) added in the third. Needs `FloorFixtures.iowa!/0`.
  """
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation

  @src Records.SourceRef.new("https://x.test/v", "v")

  @old_def [
    %{
      "level" => 3,
      "enum" => "(A)",
      "heading" => "In general",
      "text" => "The term covered investment—"
    },
    %{
      "level" => 4,
      "enum" => "(i)",
      "heading" => nil,
      "text" =>
        "means a security issued by a publicly traded company or any comparable economic interest acquired through synthetic means, such as the use of a derivative, including an option, warrant, or other similar means; and"
    }
  ]
  @new_def [
    %{
      "level" => 3,
      "enum" => "(A)",
      "heading" => "In general",
      "text" =>
        "The term covered investment means a security issued by a publicly traded company or any comparable economic interest acquired through synthetic means, such as the use of a derivative, including an option, warrant, or other similar means."
    }
  ]

  def section(enum, heading, blocks),
    do: %{"kind" => "section", "enum" => enum, "heading" => heading, "blocks" => blocks}

  def version!(bill, code, date, sections) do
    {:ok, _} =
      Ingest.write(
        %Records.BillVersion{
          jurisdiction: "federal",
          bill_external_id: bill.external_id,
          code: code,
          classification: code,
          date: date,
          source: @src
        },
        nil
      )

    if sections,
      do: :ok = Legislation.put_sections(Legislation.get_version(bill, code).id, sections, 2)

    # what the queued job stores once it runs
    :ok = EverydayCitizen.Jobs.ComputeOrigins.perform(%Oban.Job{args: %{"bill_id" => bill.id}})
  end

  @doc "Writes versions ih, rh, eh of 119-s-5; returns the bill."
  def three_versions! do
    bill = Legislation.get_bill("federal", "119-s-5")

    short =
      section("1.", "Short title", [
        %{"level" => 0, "text" => "This Act may be cited as the Stop Insider Trading Act."}
      ])

    tail = [
      %{
        "level" => 3,
        "enum" => "(B)",
        "heading" => "Exclusion",
        "text" => "The term covered investment does not include—"
      }
    ]

    restrictions = &section("2.", "Restrictions on covered investments", &1 ++ tail)

    voter_id =
      section("3.", "Requiring voters to provide photo identification", [
        %{
          "level" => 1,
          "enum" => "(a)",
          "heading" => "Requirement",
          "text" => "A valid photo identification is required."
        }
      ])

    # whitespace-only differences are not changes
    eh_short =
      section("1.", "Short title", [
        %{"level" => 0, "text" => "This Act may be cited as   the Stop Insider Trading Act."}
      ])

    version!(bill, "ih", ~D[2026-01-12], [short, restrictions.(@old_def)])
    version!(bill, "rh", ~D[2026-02-03], [short, restrictions.(@new_def)])
    version!(bill, "eh", ~D[2026-07-22], [eh_short, restrictions.(@new_def), voter_id])
    bill
  end
end
