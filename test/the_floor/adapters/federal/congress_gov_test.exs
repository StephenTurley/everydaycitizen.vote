defmodule TheFloor.Adapters.Federal.CongressGovTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.{CongressGov, HTTP}

  test "get/2 strips api_key from source url and hashes the raw body" do
    body = ~s({"bills": []})

    Req.Test.stub(TheFloor.Federal, fn conn ->
      assert conn.query_string =~ "api_key=test-key"

      assert Plug.Conn.get_req_header(conn, "user-agent") == [
               "EverydayCitizen/0.1 (+https://everydaycitizen.vote)"
             ]

      Plug.Conn.send_resp(conn, 200, body)
    end)

    assert {:ok, %{"bills" => []}, source} = CongressGov.get("/bill", limit: 5)
    refute source.url =~ "api_key"
    assert source.url =~ "https://api.congress.gov/v3/bill?"
    assert source.content_hash == :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)
  end

  test "paginate/3 follows next links" do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      params = Plug.Conn.fetch_query_params(conn).query_params

      case params["offset"] do
        nil ->
          assert params["limit"] == "250"
          next = "https://api.congress.gov/v3/bill?offset=2&limit=250&format=json"

          Req.Test.json(conn, %{
            "bills" => [%{"n" => 1}, %{"n" => 2}],
            "pagination" => %{"count" => 3, "next" => next}
          })

        "2" ->
          assert params["api_key"] == "test-key"
          Req.Test.json(conn, %{"bills" => [%{"n" => 3}], "pagination" => %{"count" => 3}})
      end
    end)

    result = CongressGov.paginate("/bill", "bills", []) |> Enum.to_list()
    assert [{%{"n" => 1}, s1}, {%{"n" => 2}, s1}, {%{"n" => 3}, s2}] = result
    assert s1.content_hash != s2.content_hash
  end

  test "count/2 returns pagination count" do
    Req.Test.stub(TheFloor.Federal, fn conn ->
      assert Plug.Conn.fetch_query_params(conn).query_params["limit"] == "1"
      Req.Test.json(conn, %{"bills" => [], "pagination" => %{"count" => 42}})
    end)

    assert {:ok, 42} = CongressGov.count("/bill")
  end

  test "get/2 returns {:error, _} after retries on 503" do
    Req.Test.stub(TheFloor.Federal, fn conn -> Plug.Conn.send_resp(conn, 503, "down") end)
    assert {:error, _} = HTTP.get("https://example.test/x")
  end
end
