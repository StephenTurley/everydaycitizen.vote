defmodule EverydayCitizenWeb.AiCrawlers do
  @moduledoc """
  Turns away crawlers that collect pages for AI companies (owner's decision,
  2026-10-26), with a 403 that points to robots.txt, which lists the same
  agents. robots.txt is still served to them, so a polite crawler learns to
  stop; this plug turns away the rest at once, before any page is rendered.
  """
  @behaviour Plug

  import Plug.Conn

  # every name here is also in priv/static/robots.txt (checked by a test)
  @agents ~w(GPTBot OAI-SearchBot ChatGPT-User ClaudeBot Claude-User Claude-SearchBot
             anthropic-ai CCBot Google-Extended Applebot-Extended PerplexityBot
             Perplexity-User Bytespider Amazonbot meta-externalagent meta-externalfetcher
             FacebookBot cohere-ai cohere-training-data-crawler Diffbot ImagesiftBot
             Omgilibot YouBot Timpibot AI2Bot DuckAssistBot MistralAI-User)

  @pattern Regex.compile!(Enum.map_join(@agents, "|", &Regex.escape/1), "i")

  @doc "The user-agent names turned away."
  @spec agents() :: [String.t()]
  def agents, do: @agents

  @doc "Whether a user agent is one of them."
  @spec ai_crawler?(String.t() | nil) :: boolean()
  def ai_crawler?(nil), do: false
  def ai_crawler?(agent), do: Regex.match?(@pattern, agent)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{request_path: "/robots.txt"} = conn, _opts), do: conn

  def call(conn, _opts) do
    if conn |> get_req_header("user-agent") |> List.first() |> ai_crawler?() do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(403, "AI crawlers are not allowed on this site; see /robots.txt.\n")
      |> halt()
    else
      conn
    end
  end
end
