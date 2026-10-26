defmodule EverydayCitizen.Adapters.Federal.Jobs.ReclassifyVotesTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.ReclassifyVotes
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Votes.Vote

  setup do
    src = Records.SourceRef.new("https://x.test/a", "a")

    for r <- [
          %Records.Jurisdiction{
            key: "federal",
            name: "F",
            classification: "federal",
            time_zone: "America/New_York",
            source: src
          },
          %Records.LegislativeSession{jurisdiction: "federal", identifier: "119", source: src},
          %Records.Body{
            jurisdiction: "federal",
            external_id: "senate",
            name: "Senate",
            classification: "chamber",
            source: src
          },
          %Records.Vote{
            jurisdiction: "federal",
            body_external_id: "senate",
            session_identifier: "119",
            external_id: "senate-119-1-1",
            question: "On the Cloture Motion",
            voted_on: ~D[2025-01-09],
            voted_at: ~U[2025-01-09 05:00:00Z],
            counts: %{yea: 1, nay: 0, present: 0, absent: 0},
            positions: [],
            source: src
          }
        ] do
      {:ok, _} = Ingest.write(r, nil)
    end

    :ok
  end

  test "stored votes get the type their question gives" do
    Repo.update_all(Vote, set: [classification: "other"])
    assert :ok = perform_job(ReclassifyVotes, %{})
    assert Repo.one!(Vote).classification == "cloture"
  end

  test "a vote written without a type is stored as other until classified" do
    assert Repo.one!(Vote).classification == "other"
  end

  test "it runs by name only" do
    assert {:ok, [{"reclassify_votes", ReclassifyVotes, _}]} =
             EverydayCitizen.Ingest.Jobs.select("reclassify_votes")

    refute Enum.any?(EverydayCitizen.Ingest.Jobs.all(), &(elem(&1, 0) == "reclassify_votes"))
  end
end
