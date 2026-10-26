defmodule EverydayCitizen.Adapters.Federal.Jobs.LinkVoteSubjectsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Adapters.Federal.Jobs.LinkVoteSubjects
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Votes.Vote

  @dir "test/support/fixtures/federal/congress_gov"

  setup do
    EverydayCitizen.FloorFixtures.iowa!()

    for {roll, question, description, ref, bill} <- [
          {9, "On the Nomination", "Todd Blanche, of Florida, to be Attorney General", "PN1078",
           nil},
          {10, "On the Nomination", "Francis Brooke, of Virginia, to be Deputy Secretary",
           "PN73011", nil},
          {249, "On the Amendment", "To improve the bill.", nil, "119-s-5"}
        ] do
      {:ok, _} =
        Ingest.write(
          %Records.Vote{
            jurisdiction: "federal",
            body_external_id: "senate",
            session_identifier: "119-2",
            external_id: "senate-119-2-#{roll}",
            identifier: "Roll Call #{roll}",
            question: question,
            description: description,
            subject_ref: ref,
            voted_on: ~D[2026-09-28],
            voted_at: ~U[2026-09-28 16:00:00Z],
            bill_external_id: bill,
            source: Records.SourceRef.new("https://x.test/v", "v")
          },
          nil
        )
    end

    :ok
  end

  defp stub do
    test = self()

    Req.Test.stub(EverydayCitizen.Federal, fn conn ->
      send(test, {:path, conn.request_path})

      file =
        case conn.request_path do
          "/v3/nomination/119" -> "nomination_list.json"
          "/v3/bill/119/s/5/amendments" -> "bill_119_s_4668_amendments.json"
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, File.read!("#{@dir}/#{file}"))
    end)
  end

  defp link(roll),
    do:
      Repo.one!(
        from v in Vote,
          where: v.external_id == ^"senate-119-2-#{roll}",
          select: {v.subject_ref, v.subject_url}
      )

  test "links nominations and amendments to their official pages, leaving mismatches unlinked" do
    stub()
    assert :ok = perform_job(LinkVoteSubjects, %{"congress" => 119})

    assert link(9) == {"PN1078", "https://www.congress.gov/nomination/119th-congress/1078"}
    assert link(10) == {"PN73011", nil}

    assert link(249) ==
             {"SAMDT6835",
              "https://www.congress.gov/amendment/119th-congress/senate-amendment/6835"}

    assert EverydayCitizen.Provenance.last_succeeded_run("federal", "link_vote_subjects").stats ==
             %{"nominations" => 1, "amendments" => 1, "unlinked" => 1}
  end

  test "votes already linked are not looked up again" do
    stub()
    assert :ok = perform_job(LinkVoteSubjects, %{"congress" => 119})
    flush_paths()

    assert :ok = perform_job(LinkVoteSubjects, %{"congress" => 119})
    # only the unlinked nomination is still wanted
    assert_received {:path, "/v3/nomination/119"}
    refute_received {:path, "/v3/bill/119/s/5/amendments"}
  end

  defp flush_paths do
    receive do
      {:path, _} -> flush_paths()
    after
      0 -> :ok
    end
  end
end
