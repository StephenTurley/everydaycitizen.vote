defmodule EverydayCitizen.Summaries.WriterTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Writer

  defp stub_claude do
    test = self()

    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = Jason.decode!(body)
      send(test, {:call, body})
      [%{"content" => content}] = body["messages"]

      text =
        if String.contains?(content, "<part>") and not String.contains?(content, "Length:"),
          do: "- part summary",
          else: "Final summary."

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "model" => "claude-haiku-5-5",
          "content" => [%{"type" => "text", "text" => text}],
          "usage" => %{"input_tokens" => 1_000, "output_tokens" => 50}
        })
      )
    end)
  end

  test "the length band follows the bill's size" do
    assert Writer.band(String.duplicate("a", 9_000)) == {"short", 300}
    assert Writer.band(String.duplicate("a", 40_000)) == {"medium", 500}
    assert Writer.band(String.duplicate("a", 200_000)) == {"long", 900}
    assert Writer.band(String.duplicate("a", 300_000)) == {"very long", 1400}
  end

  test "a short bill is one request with its length band" do
    stub_claude()

    assert {:ok, %{summary: "Final summary.", input_tokens: 1_000}} =
             Writer.write(:bill, "SEC. 1. Short text.")

    assert_received {:call, body}
    assert body["max_tokens"] == 300

    assert [%{"content" => "Length: short\n\n<bill>\nSEC. 1. Short text.\n</bill>"}] =
             body["messages"]

    refute_received {:call, _}
    assert_in_delta Summaries.spent_today_usd(), 0.000125, 0.000001
  end

  test "a very long bill is summarized part by part at section breaks, then combined" do
    stub_claude()
    section = "SEC. 1. " <> String.duplicate("word ", 20_000) <> "\n"
    text = String.duplicate(section, 3)
    assert String.length(text) == 300_027

    assert {:ok, %{summary: "Final summary.", input_tokens: 3_000}} = Writer.write(:bill, text)

    assert_received {:call, %{"messages" => [%{"content" => "<part>\n" <> first}]}}
    assert_received {:call, %{"messages" => [%{"content" => "<part>\n" <> second}]}}
    assert_received {:call, final}

    for part <- [first, second] do
      assert String.length(part) <= 250_000 + 9
      assert String.starts_with?(part, "SEC. 1.")
    end

    assert final["max_tokens"] == 1400
    assert [%{"content" => "Length: very long\n\n<bill>\n" <> combined}] = final["messages"]
    assert combined =~ "<part>\n- part summary\n</part>"
  end

  test "a long bill's finished parts are kept, so a retry pays only for what is left" do
    test = self()
    {:ok, final_fails} = Agent.start_link(fn -> true end)

    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      [%{"content" => content}] = Jason.decode!(body)["messages"]
      final? = String.contains?(content, "Length:")
      send(test, {:call, if(final?, do: :final, else: :part)})

      if final? and Agent.get(final_fails, & &1) do
        Plug.Conn.send_resp(conn, 500, "")
      else
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            "model" => "claude-haiku-5-5",
            "content" => [%{"type" => "text", "text" => "- summary"}],
            "usage" => %{"input_tokens" => 1_000, "output_tokens" => 50}
          })
        )
      end
    end)

    text = String.duplicate("SEC. 1. " <> String.duplicate("word ", 20_000) <> "\n", 3)

    assert {:error, _} = Writer.write(:bill, text)
    assert_received {:call, :part}
    assert_received {:call, :part}
    assert_received {:call, :final}

    Agent.update(final_fails, fn _ -> false end)
    assert {:ok, %{summary: "- summary"}} = Writer.write(:bill, text)
    assert_received {:call, :final}
    refute_received {:call, _}
  end

  test "once the budget is spent, a long bill stops before its next call" do
    stub_claude()

    for _ <- 1..200,
        do: :ok = Summaries.record_usage(:section, %{input_tokens: 100_000, output_tokens: 0})

    assert {:error, :paused} = Writer.write(:bill, String.duplicate("SEC. 1. x\n", 40_000))
    refute_received {:call, _}
  end
end
