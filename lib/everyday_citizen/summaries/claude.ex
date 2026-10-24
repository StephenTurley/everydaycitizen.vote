defmodule EverydayCitizen.Summaries.Claude do
  @moduledoc """
  Writes a plain-English summary of a section with the Claude Messages API.
  The system prompt is the published file `priv/prompts/section_summary.<v>.md`;
  the section goes in the user message between `<section>` tags, as data.
  A short reply cap keeps it cheap (this model does not take a temperature).
  """

  alias EverydayCitizen.Summaries.Credentials

  @url "https://api.anthropic.com/v1/messages"
  @max_tokens 400

  @type result :: %{
          summary: String.t(),
          model: String.t(),
          input_tokens: integer() | nil,
          output_tokens: integer() | nil
        }

  @doc "Whether summaries can be written (credentials are configured)."
  @spec enabled?() :: boolean()
  def enabled?, do: Credentials.configured?()

  @spec summarize(String.t()) :: {:ok, result()} | {:error, term()}
  def summarize(text) when is_binary(text) do
    with {:ok, header} <- Credentials.auth_header() do
      body = %{
        model: config(:model),
        max_tokens: @max_tokens,
        system: prompt(),
        messages: [%{role: "user", content: "<section>\n#{text}\n</section>"}]
      }

      [
        url: @url,
        json: body,
        headers: [header, {"anthropic-version", "2023-06-01"}],
        receive_timeout: 60_000
      ]
      |> Keyword.merge(Application.get_env(:everyday_citizen, :anthropic_req_options, []))
      |> Req.post()
      |> parse()
    end
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

  defp prompt do
    path =
      Application.app_dir(
        :everyday_citizen,
        "priv/prompts/section_summary.#{config(:prompt_version)}.md"
      )

    File.read!(path)
  end

  defp config(key), do: Application.fetch_env!(:everyday_citizen, :summaries)[key]
end
