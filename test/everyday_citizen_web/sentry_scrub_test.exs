defmodule EverydayCitizenWeb.SentryScrubTest do
  use ExUnit.Case, async: true

  alias EverydayCitizenWeb.SentryScrub

  test "url drops the query string, which may hold a visitor's address" do
    conn = Plug.Test.conn(:get, "https://everydaycitizen.vote/reps?address=1+Main+St")
    assert SentryScrub.url(conn) == "https://everydaycitizen.vote/reps"
  end

  test "headers keep the default scrubbing, and the referer loses its query string" do
    conn =
      Plug.Test.conn(:get, "/bills/119-s-5")
      |> Plug.Conn.put_req_header("referer", "https://everydaycitizen.vote/search?q=123+Main+St")
      |> Plug.Conn.put_req_header("authorization", "Bearer secret")
      |> Plug.Conn.put_req_header("user-agent", "UA")

    headers = SentryScrub.headers(conn)
    assert headers["referer"] == "https://everydaycitizen.vote/search"
    assert headers["user-agent"] == "UA"
    refute Map.has_key?(headers, "authorization")
    refute inspect(headers) =~ "Main"
  end

  test "bodies and cookies are never sent" do
    conn = Plug.Test.conn(:post, "/reps", %{"address" => "1 Main St"})
    assert SentryScrub.nothing(conn) == %{}
  end

  describe "before_send/1" do
    defp crash_event do
      %Sentry.Event{
        event_id: Sentry.UUID.uuid4_hex(),
        timestamp: "2026-10-25T12:00:00Z",
        message: %Sentry.Interfaces.Message{formatted: "GenServer #PID<0.1.0> terminating"},
        level: :error,
        tags: %{"live_view" => "SearchLive"},
        extra: %{
          :genserver_state => "%{assigns: %{query: %{text: \"123 Main St\"}}}",
          :last_message =>
            ~s({:join, %{"url" => "https://everydaycitizen.vote/search?q=123+Main+St"}}),
          :pid_which_sent_last_message => "#PID<0.2.0>",
          "page" => "https://everydaycitizen.vote/search?q=50309#top",
          "note" => "kept as is",
          "nested" => %{"url" => "wss://everydaycitizen.vote/live/websocket?_csrf=x&vsn=2"}
        },
        request: %Sentry.Interfaces.Request{
          method: "GET",
          url: "https://everydaycitizen.vote/search?q=123+Main+St",
          query_string: "q=123+Main+St",
          headers: %{
            "referer" => "https://everydaycitizen.vote/search?q=50309",
            "user-agent" => "UA"
          }
        }
      }
    end

    test "drops the process state and last message, and every URL's query string" do
      event = SentryScrub.before_send(crash_event())

      refute Map.has_key?(event.extra, :genserver_state)
      refute Map.has_key?(event.extra, :last_message)
      assert event.extra["page"] == "https://everydaycitizen.vote/search#top"
      assert event.extra["nested"]["url"] == "wss://everydaycitizen.vote/live/websocket"
      assert event.request.url == "https://everydaycitizen.vote/search"
      assert event.request.query_string == nil
      assert event.request.headers["referer"] == "https://everydaycitizen.vote/search"
      refute inspect(event) =~ "Main"
      refute inspect(event) =~ "50309"
    end

    test "leaves every other field alone" do
      before = crash_event()
      event = SentryScrub.before_send(before)

      assert event.extra.pid_which_sent_last_message == "#PID<0.2.0>"
      assert event.extra["note"] == "kept as is"
      assert event.request.method == "GET"
      assert event.request.headers["user-agent"] == "UA"

      assert Map.drop(event, [:extra, :request]) == Map.drop(before, [:extra, :request])
    end

    test "an event without a request or extras passes through" do
      event = %{crash_event() | request: nil, extra: %{}}
      assert SentryScrub.before_send(event) == event
    end

    test "is the before_send callback in every environment" do
      assert Application.get_env(:sentry, :before_send) == {SentryScrub, :before_send}
    end
  end
end
