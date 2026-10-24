defmodule EverydayCitizen.Digest.Email do
  @moduledoc """
  The daily email: the changes to what a person follows, each linked to its
  page, and one-click unsubscribe (a link, plus the `List-Unsubscribe` and
  `List-Unsubscribe-Post` headers mail programs use). It describes events, never
  why they happened.
  """
  import Swoosh.Email

  alias EverydayCitizen.Accounts.User
  alias EverydayCitizen.Digest

  @spec build(User.t(), [Digest.item()]) :: Swoosh.Email.t()
  def build(%User{} = user, items) do
    unsubscribe = url("/unsubscribe/#{Digest.unsubscribe_token(user)}")

    new()
    |> to(user.email)
    |> EverydayCitizen.Mailer.sender()
    |> subject(subject(items))
    |> header("List-Unsubscribe", "<#{unsubscribe}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> text_body(text(items, unsubscribe))
    |> html_body(html(items, unsubscribe))
  end

  defp subject([_]), do: "1 update on what you follow"
  defp subject(items), do: "#{length(items)} updates on what you follow"

  defp text(items, unsubscribe) do
    lines =
      Enum.map_join(items, "\n\n", fn item ->
        [date(item), item.title, item.detail, item.url && link(item.url)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n")
      end)

    """
    What changed on the bills and reps you follow.

    #{lines}

    Everyday Citizen. Every item links to its page and the official record.
    Stop these emails: #{unsubscribe}
    """
  end

  defp html(items, unsubscribe) do
    rows =
      Enum.map_join(items, "", fn item ->
        title =
          if item.url,
            do:
              ~s(<a href="#{escape(link(item.url))}" style="color:#0b5563;font-weight:600">#{escape(item.title)}</a>),
            else: ~s(<strong>#{escape(item.title)}</strong>)

        """
        <tr><td style="padding:12px 0;border-bottom:1px solid #e6e8eb">
        <div style="font-size:13px;color:#4a5058">#{escape(date(item) || "")}</div>
        <div style="font-size:16px;margin:2px 0">#{title}</div>
        <div style="font-size:14px;color:#3a4048">#{escape(item.detail)}</div>
        </td></tr>
        """
      end)

    """
    <!doctype html>
    <html><body style="margin:0;padding:24px;background:#f4f5f6;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#15171a">
    <div style="max-width:560px;margin:0 auto;background:#fff;border:1px solid #dadde1;border-radius:12px;padding:20px">
    <p style="margin:0 0 8px;font-size:18px;font-weight:700">What changed on the bills and reps you follow</p>
    <table role="presentation" style="width:100%;border-collapse:collapse">#{rows}</table>
    <p style="margin:16px 0 0;font-size:12px;color:#4a5058">Everyday Citizen. Every item links to its page and the official record.
    <a href="#{escape(unsubscribe)}" style="color:#4a5058">Stop these emails</a></p>
    </div></body></html>
    """
  end

  defp date(%{date: nil}), do: nil
  defp date(%{date: date}), do: Calendar.strftime(date, "%A, %b %-d")

  # bill pages are paths on this site; a vote without a bill links its record
  defp link("/" <> _ = path), do: url(path)
  defp link(url), do: url

  defp url(path), do: EverydayCitizenWeb.Endpoint.url() <> path

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
