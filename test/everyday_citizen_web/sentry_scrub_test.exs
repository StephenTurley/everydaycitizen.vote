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

  test "headers never carry the visitor's IP address" do
    conn =
      Enum.reduce(
        ~w(x-forwarded-for fly-client-ip x-real-ip forwarded true-client-ip cf-connecting-ip),
        Plug.Test.conn(:get, "/bills/119-s-5"),
        &Plug.Conn.put_req_header(&2, &1, "203.0.113.7")
      )

    refute inspect(SentryScrub.headers(conn)) =~ "203.0.113.7"
  end

  test "the remote address is never read" do
    conn = %{Plug.Test.conn(:get, "/") | remote_ip: {203, 0, 113, 7}}
    assert SentryScrub.remote_address(conn) == ""
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
            "user-agent" => "UA",
            "x-forwarded-for" => "203.0.113.7",
            "fly-client-ip" => "203.0.113.7"
          },
          env: %{"REMOTE_ADDR" => "203.0.113.7", "SERVER_PORT" => 443}
        },
        user: %{id: 1, ip_address: "203.0.113.7"}
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

    test "drops the visitor's IP address wherever the event holds it" do
      event = SentryScrub.before_send(crash_event())

      refute inspect(event) =~ "203.0.113.7"
      assert event.request.env == %{"SERVER_PORT" => 443}
      assert event.user == %{id: 1}
    end

    test "leaves every other field alone" do
      before = crash_event()
      event = SentryScrub.before_send(before)

      assert event.extra.pid_which_sent_last_message == "#PID<0.2.0>"
      assert event.extra["note"] == "kept as is"
      assert event.request.method == "GET"
      assert event.request.headers["user-agent"] == "UA"

      assert Map.drop(event, [:extra, :request, :user]) ==
               Map.drop(before, [:extra, :request, :user])
    end

    test "an event without a request or extras passes through" do
      event = %{crash_event() | request: nil, extra: %{}, user: %{}}
      assert SentryScrub.before_send(event) == event
    end

    test "anything but an event passes through unchanged" do
      transaction = %Sentry.Transaction{
        event_id: "e",
        span_id: "s",
        start_timestamp: 1,
        timestamp: 2,
        transaction: "/search?q=50309"
      }

      assert SentryScrub.before_send(transaction) == transaction
      assert SentryScrub.before_send(:other) == :other
    end

    test "odd terms in extras never stop the event, and risky extras still go" do
      event = %{
        crash_event()
        | extra:
            Map.merge(crash_event().extra, %{
              "improper" => [1 | "https://x.test/a?q=1"],
              "tuple" => {:ok, "https://x.test/b?q=2"},
              "pid" => self(),
              # invalid UTF-8: the URL regex cannot read it, so it is dropped
              "unreadable" => <<"https://x.test/c?q=3", 0xFF>>
            })
      }

      scrubbed = SentryScrub.before_send(event)
      assert %Sentry.Event{} = scrubbed
      refute Map.has_key?(scrubbed.extra, :genserver_state)
      refute Map.has_key?(scrubbed.extra, :last_message)
      refute inspect(scrubbed) =~ "q=1"
      refute inspect(scrubbed) =~ "q=2"
      refute inspect(scrubbed) =~ "Main"
      assert scrubbed.extra["pid"] == self()
      refute Map.has_key?(scrubbed.extra, "unreadable")
      assert scrubbed.extra["note"] == "kept as is"
      assert scrubbed.request.url == "https://everydaycitizen.vote/search"
    end

    test "is the before_send callback in every environment" do
      assert Application.get_env(:sentry, :before_send) == {SentryScrub, :before_send}
    end
  end
end
