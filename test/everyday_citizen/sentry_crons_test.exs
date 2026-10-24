defmodule EverydayCitizen.SentryCronsTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.SentryCrons

  defp cron_job do
    %Oban.Job{
      id: 1,
      worker: "EverydayCitizen.Nightly.Check",
      meta: %{"cron" => true, "cron_expr" => "0 6 * * *", "cron_tz" => "America/New_York"}
    }
  end

  defp recorder do
    test = self()

    fn opts ->
      send(test, {:check_in, opts})
      {:ok, "abc"}
    end
  end

  test "a scheduled run reports its start and its success to one monitor" do
    assert :ok = SentryCrons.monitor(cron_job(), fn -> :ok end, send: recorder())

    assert_received {:check_in, start}
    assert start[:status] == :in_progress
    assert start[:monitor_slug] == "everyday-citizen-nightly-check"

    assert start[:monitor_config] == [
             schedule: [type: :crontab, value: "0 6 * * *"],
             timezone: "America/New_York"
           ]

    assert_received {:check_in, finish}
    assert finish[:status] == :ok
    assert finish[:check_in_id] == "abc"
    assert finish[:monitor_slug] == "everyday-citizen-nightly-check"
    assert is_number(finish[:duration])
  end

  test "an explicit slug keeps an existing monitor" do
    :ok = SentryCrons.monitor(cron_job(), fn -> :ok end, send: recorder(), slug: "kept-slug")
    assert_received {:check_in, start}
    assert start[:monitor_slug] == "kept-slug"
  end

  test "a run that returns an error is reported as failed and returns the error" do
    assert {:error, :boom} =
             SentryCrons.monitor(cron_job(), fn -> {:error, :boom} end, send: recorder())

    assert_received {:check_in, _start}
    assert_received {:check_in, finish}
    assert finish[:status] == :error
  end

  test "a run that raises is reported as failed and the exception is raised again" do
    assert_raise RuntimeError, fn ->
      SentryCrons.monitor(cron_job(), fn -> raise "boom" end, send: recorder())
    end

    assert_received {:check_in, _start}
    assert_received {:check_in, finish}
    assert finish[:status] == :error
  end

  test "a run that was not scheduled (enqueued by hand) reports nothing" do
    job = %{cron_job() | meta: %{}}

    assert :ok = SentryCrons.monitor(job, fn -> :ok end, send: recorder())
    refute_received {:check_in, _}
  end
end
