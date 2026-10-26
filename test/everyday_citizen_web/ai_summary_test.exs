defmodule EverydayCitizenWeb.AiSummaryTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.{RateLimit, Summaries}
  alias EverydayCitizenWeb.AiSummary

  defp socket(opts) do
    %Phoenix.LiveView.Socket{
      transport_pid: if(opts[:live], do: self()),
      assigns: %{
        __changed__: %{},
        crawler: opts[:crawler] || false,
        remote_ip: opts[:ip] || "203.0.113.#{System.unique_integer([:positive])}"
      }
    }
  end

  defp never, do: fn -> flunk("no summary should be asked for") end

  test "a cached summary is shown and nothing is asked for" do
    for opts <- [[live: true], [live: false], [crawler: true]],
        do: assert(AiSummary.state(socket(opts), %{summary: "S."}, never()) == {:ok, "S."})
  end

  test "a crawler, or a page not yet live, asks for nothing" do
    assert AiSummary.state(socket(live: true, crawler: true), nil, never()) == :none
    assert AiSummary.state(socket(live: false), nil, never()) == :loading
  end

  test "past the visitor's hourly limit, nothing is asked for" do
    ip = "203.0.113.250"

    for _ <- 1..Summaries.visitor_limit(),
        do: RateLimit.hit({:summaries, ip}, Summaries.visitor_limit(), :timer.hours(1))

    assert AiSummary.state(socket(live: true, ip: ip), nil, never()) == :limited
  end

  test "otherwise the summary is asked for, once" do
    test = self()

    request = fn ->
      send(test, :asked)
      :queued
    end

    assert AiSummary.state(socket(live: true), nil, request) == :loading
    assert_received :asked
    refute_received :asked
  end

  test "a result is shown only for the subject still on the page" do
    socket = Phoenix.Component.assign(socket(live: true), :week_summary, {"week:1", :loading})
    assert AiSummary.put_result(socket, :week_summary, "week:2", {:ok, "Old."}) == socket

    assert AiSummary.put_result(socket, :week_summary, "week:1", {:ok, "New."}).assigns.week_summary ==
             {"week:1", {:ok, "New."}}
  end

  test "loading another summary under the same key stops listening for the first" do
    socket = AiSummary.load(socket(live: true), :week_summary, :rep_week, {"week:a", "input a"})
    assert {"week:a", :loading} = socket.assigns.week_summary

    socket = AiSummary.load(socket, :week_summary, :rep_week, {"week:b", "input b"})
    assert {"week:b", :loading} = socket.assigns.week_summary

    for subject <- ["week:a", "week:b"],
        do:
          Phoenix.PubSub.broadcast(
            EverydayCitizen.PubSub,
            Summaries.ai_topic(:rep_week, subject),
            subject
          )

    assert_receive "week:b"
    refute_receive "week:a", 50

    assert AiSummary.load(socket, :week_summary, :rep_week, nil).assigns.week_summary == nil
  end
end
