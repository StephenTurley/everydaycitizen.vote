defmodule EverydayCitizenWeb.CrawlerTest do
  use ExUnit.Case, async: true

  alias EverydayCitizenWeb.Crawler

  test "search, preview and scripted clients are crawlers" do
    for ua <- [
          "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
          "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
          "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2)",
          "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 HeadlessChrome/130.0 Safari/537.36",
          "curl/8.7.1",
          "python-requests/2.32",
          "Go-http-client/2.0",
          ""
        ],
        do: assert(Crawler.user_agent?(ua), ua)
  end

  test "browsers are not" do
    for ua <- [
          "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.6; rv:131.0) Gecko/20100101 Firefox/131.0"
        ],
        do: refute(Crawler.user_agent?(ua), ua)
  end
end
