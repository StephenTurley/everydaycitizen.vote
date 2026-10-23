defmodule TheFloorWeb.SentryScrubTest do
  use ExUnit.Case, async: true

  alias TheFloorWeb.SentryScrub

  test "url drops the query string, which may hold a visitor's address" do
    conn = Plug.Test.conn(:get, "https://thefloor.vote/reps?address=1+Main+St")
    assert SentryScrub.url(conn) == "https://thefloor.vote/reps"
  end

  test "bodies and cookies are never sent" do
    conn = Plug.Test.conn(:post, "/reps", %{"address" => "1 Main St"})
    assert SentryScrub.nothing(conn) == %{}
  end
end
