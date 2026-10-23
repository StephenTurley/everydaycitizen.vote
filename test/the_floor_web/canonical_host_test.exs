defmodule TheFloorWeb.CanonicalHostTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias TheFloorWeb.CanonicalHost

  defp call(url, canonical) do
    conn(:get, url) |> CanonicalHost.call(CanonicalHost.init(host: canonical))
  end

  test "another host redirects permanently to the canonical one, keeping path and query" do
    conn = call("https://thefloor-vote.fly.dev/bills/119-hr-22?tab=votes", "thefloor.vote")

    assert conn.halted
    assert conn.status == 301

    assert Plug.Conn.get_resp_header(conn, "location") == [
             "https://thefloor.vote/bills/119-hr-22?tab=votes"
           ]
  end

  test "www redirects to the bare domain" do
    conn = call("https://www.thefloor.vote/", "thefloor.vote")
    assert Plug.Conn.get_resp_header(conn, "location") == ["https://thefloor.vote/"]
  end

  test "the canonical host passes through" do
    refute call("https://thefloor.vote/", "thefloor.vote").halted
  end

  test "no canonical host configured passes everything through" do
    refute call("http://localhost:4000/", nil).halted
  end
end
