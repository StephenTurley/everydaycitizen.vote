defmodule EverydayCitizen.Summaries.ClaudeTest do
  use ExUnit.Case, async: true

  alias EverydayCitizen.Summaries.Claude

  defp reply(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  test "sends the published prompt and the section as data, and returns the summary" do
    test = self()

    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:request, conn.request_path, Map.new(conn.req_headers), Jason.decode!(body)})

      reply(conn, 200, %{
        "model" => "claude-haiku-5-5",
        "content" => [%{"type" => "text", "text" => "This section names the bill."}],
        "usage" => %{"input_tokens" => 210, "output_tokens" => 12}
      })
    end)

    assert {:ok,
            %{
              summary: "This section names the bill.",
              model: "claude-haiku-5-5",
              input_tokens: 210,
              output_tokens: 12
            }} = Claude.summarize("Sec. 1. Short title\nThis Act may be cited as the Sample Act.")

    assert_received {:request, "/v1/messages", headers, body}
    assert headers["x-api-key"] == "test-anthropic-key"
    assert headers["anthropic-version"] == "2023-06-01"
    assert body["model"] == "claude-haiku-5-5"
    refute Map.has_key?(body, "temperature")
    assert body["max_tokens"] == 300
    # with thinking on, the model can spend the whole reply cap thinking and return no text
    assert body["thinking"] == %{"type" => "disabled"}

    assert body["system"] ==
             File.read!(
               Application.app_dir(:everyday_citizen, "priv/prompts/section_summary.v2.md")
             )

    assert [%{"role" => "user", "content" => content}] = body["messages"]
    assert content =~ "<section>\nSec. 1. Short title"
    assert content =~ "</section>"
  end

  test "an error status is returned, not raised" do
    for status <- [429, 500, 401] do
      Req.Test.stub(EverydayCitizen.Claude, &reply(&1, status, %{"type" => "error"}))
      assert {:error, {:http_status, ^status}} = Claude.summarize("text")
    end
  end

  test "each kind uses its own published prompt, tag and reply cap; options can override" do
    test = self()

    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:body, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{"content" => [%{"type" => "text", "text" => "ok"}]})
      )
    end)

    prompt = &File.read!(Application.app_dir(:everyday_citizen, "priv/prompts/#{&1}"))

    for {kind, file, tag, cap} <- [
          {:section, "section_summary.v2.md", "section", 300},
          {:bill, "bill_summary.v2.md", "bill", 800},
          {:bill_chunk, "bill_chunk.v2.md", "part", 600},
          {:rep_week, "rep_week.v1.md", "activity", 300}
        ] do
      {:ok, _} = Claude.summarize("input", kind)
      assert_received {:body, body}
      assert body["system"] == prompt.(file)
      assert body["max_tokens"] == cap
      assert [%{"content" => content}] = body["messages"]
      assert content == "<#{tag}>\ninput\n</#{tag}>"
    end

    {:ok, _} = Claude.summarize("input", :bill, max_tokens: 900, note: "Length: long")
    assert_received {:body, body}
    assert body["max_tokens"] == 900
    assert [%{"content" => "Length: long\n\n<bill>\ninput\n</bill>"}] = body["messages"]
  end
end
