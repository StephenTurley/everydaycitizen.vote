defmodule EverydayCitizenWeb.SentryContextTest do
  use EverydayCitizenWeb.ConnCase, async: true

  # what the endpoint hands Sentry for a request, should it error
  test "a request's error context holds no IP address", %{conn: conn} do
    conn
    |> Map.put(:remote_ip, {203, 0, 113, 7})
    |> put_req_header("x-forwarded-for", "203.0.113.7")
    |> put_req_header("fly-client-ip", "203.0.113.7")
    |> get(~p"/")

    request = Sentry.Context.get_all()[:request]
    assert request[:env]["REMOTE_ADDR"] == ""
    refute inspect(request) =~ "203.0.113.7"
  end
end
