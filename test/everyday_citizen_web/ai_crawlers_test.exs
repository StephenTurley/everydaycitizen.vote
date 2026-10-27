defmodule EverydayCitizenWeb.AiCrawlersTest do
  use EverydayCitizenWeb.ConnCase, async: true

  @gptbot "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.4; +https://openai.com/gptbot)"
  @claudebot "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; ClaudeBot/1.0; +claudebot@anthropic.com)"
  @googlebot "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"

  setup do
    EverydayCitizen.FloorFixtures.iowa!()
    :ok
  end

  defp as(conn, agent), do: put_req_header(conn, "user-agent", agent)

  test "AI crawlers are turned away from every page", %{conn: conn} do
    for agent <- [@gptbot, @claudebot], path <- ["/", "/bills/119-s-5", "/this-week"] do
      assert conn |> as(agent) |> get(path) |> response(403) =~ "robots.txt"
    end
  end

  test "AI crawlers can still read robots.txt", %{conn: conn} do
    assert conn |> as(@gptbot) |> get("/robots.txt") |> response(200) =~ "GPTBot"
  end

  test "search engines and people get the pages", %{conn: conn} do
    assert conn |> as(@googlebot) |> get("/bills/119-s-5") |> html_response(200)
    assert conn |> as("Mozilla/5.0 (Macintosh)") |> get("/bills/119-s-5") |> html_response(200)
  end

  test "robots.txt keeps crawlers off links with a query and AI crawlers off everything", %{
    conn: conn
  } do
    robots = conn |> get("/robots.txt") |> response(200)
    assert robots =~ ~r/User-agent: \*\nDisallow: \/\*\?/
    assert robots =~ ~r/User-agent: GPTBot\n(User-agent: .+\n)*Disallow: \/\n/
    assert robots =~ "User-agent: ClaudeBot"
    assert robots =~ "User-agent: CCBot"
  end

  test "every AI crawler turned away is also named in robots.txt", %{conn: conn} do
    robots = conn |> get("/robots.txt") |> response(200)

    for agent <- EverydayCitizenWeb.AiCrawlers.agents(),
        do: assert(robots =~ "User-agent: #{agent}\n")
  end

  test "a bill page names its plain address as the canonical one", %{conn: conn} do
    html = conn |> get("/bills/119-s-5?section=0") |> html_response(200)

    assert html =~
             ~s(<link rel="canonical" href="#{EverydayCitizenWeb.Endpoint.url()}/bills/119-s-5")
  end
end
