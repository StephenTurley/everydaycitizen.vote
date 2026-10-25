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
end
