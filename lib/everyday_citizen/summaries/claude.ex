defmodule EverydayCitizen.Summaries.Claude do
  @moduledoc """
  Writes plain-English summaries with the Claude Messages API. Each kind has a
  published system prompt (`priv/prompts/<file>.<version>.md`), a tag the input
  goes in as data, and a reply cap: `:section`, `:bill`, `:bill_chunk` (one part
  of a long bill) and `:rep_week`. Options: `:max_tokens` (override the cap) and
  `:note` (a line before the input, such as the bill's length band). This model
  takes no temperature.
  """

  alias EverydayCitizen.Summaries.Credentials

  @url "https://api.anthropic.com/v1/messages"

  # kind => {prompt file stem, input tag, default reply cap}
  @kinds %{
    section: {"section_summary", "section", 300},
    bill: {"bill_summary", "bill", 500},
    bill_chunk: {"bill_chunk", "part", 600},
    rep_week: {"rep_week", "activity", 300}
  }

  @type result :: %{
          summary: String.t(),
          model: String.t(),
          input_tokens: integer() | nil,
          output_tokens: integer() | nil
        }

  @doc "Whether summaries can be written (credentials are configured)."
  @spec enabled?() :: boolean()
  def enabled?, do: Credentials.configured?()

  @spec summarize(String.t(), atom(), keyword()) :: {:ok, result()} | {:error, term()}
  def summarize(text, kind \\ :section, opts \\ []) when is_binary(text) do
    {stem, tag, cap} = Map.fetch!(@kinds, kind)

    with {:ok, header} <- Credentials.auth_header() do
      input = "<#{tag}>\n#{text}\n</#{tag}>"

      body = %{
        model: config(:model),
        max_tokens: Keyword.get(opts, :max_tokens, cap),
        system: prompt(stem, kind),
        messages: [
          %{role: "user", content: if(note = opts[:note], do: "#{note}\n\n#{input}", else: input)}
        ]
      }

      [
        url: @url,
        json: body,
        headers: [header, {"anthropic-version", "2023-06-01"}],
        receive_timeout: 120_000
      ]
      |> Keyword.merge(Application.get_env(:everyday_citizen, :anthropic_req_options, []))
      |> Req.post()
      |> parse()
    end
  end

  @doc "The published prompt file's path on GitHub for a kind (for the AI label link)."
  @spec prompt_path(atom()) :: String.t()
  def prompt_path(kind) do
    {stem, _, _} = Map.fetch!(@kinds, kind)
    "priv/prompts/#{stem}.#{EverydayCitizen.Summaries.prompt_version(kind)}.md"
  end

  defp parse({:ok, %Req.Response{status: 200, body: %{"content" => content} = body}}) do
    case for(%{"type" => "text", "text" => t} <- content, do: t)
         |> Enum.join()
         |> String.trim() do
      "" ->
        {:error, :empty}

      summary ->
        {:ok,
         %{
           summary: summary,
           model: body["model"] || config(:model),
           input_tokens: get_in(body, ["usage", "input_tokens"]),
           output_tokens: get_in(body, ["usage", "output_tokens"])
         }}
    end
  end

  defp parse({:ok, %Req.Response{status: status}}), do: {:error, {:http_status, status}}
  defp parse({:error, reason}), do: {:error, reason}

  defp prompt(stem, kind) do
    version = EverydayCitizen.Summaries.prompt_version(kind)
    File.read!(Application.app_dir(:everyday_citizen, "priv/prompts/#{stem}.#{version}.md"))
  end

  defp config(key), do: Application.fetch_env!(:everyday_citizen, :summaries)[key]
end
