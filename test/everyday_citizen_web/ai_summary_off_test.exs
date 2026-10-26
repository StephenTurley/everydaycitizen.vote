defmodule EverydayCitizenWeb.AiSummaryOffTest do
  # not async: it switches summaries off for the whole app
  use EverydayCitizen.DataCase, async: false

  alias EverydayCitizenWeb.AiSummary

  setup do
    key = Application.get_env(:everyday_citizen, :anthropic_api_key)
    Application.put_env(:everyday_citizen, :anthropic_api_key, nil)
    on_exit(fn -> Application.put_env(:everyday_citizen, :anthropic_api_key, key) end)
  end

  # building a summary's input can read a whole bill's text
  test "with summaries off, the summary's input is never built" do
    socket = %Phoenix.LiveView.Socket{
      transport_pid: self(),
      assigns: %{__changed__: %{}, crawler: false, remote_ip: "203.0.113.9"}
    }

    socket = AiSummary.load(socket, :week_summary, :rep_week, fn -> flunk("input built") end)
    assert socket.assigns.week_summary == nil
  end
end
