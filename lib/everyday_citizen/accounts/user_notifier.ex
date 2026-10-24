defmodule EverydayCitizen.Accounts.UserNotifier do
  @moduledoc "Account emails: sign-in links and email-change confirmations."
  import Swoosh.Email

  alias EverydayCitizen.Accounts.User
  alias EverydayCitizen.Mailer

  # Delivers the email, plain and formatted: a line, the link (a button in the
  # formatted version), and a closing note.
  defp deliver(recipient, subject, {intro, url, button, outro}) do
    email =
      new()
      |> to(recipient)
      |> Mailer.sender()
      |> subject(subject)
      |> text_body("#{intro}\n\n#{url}\n\n#{outro}\n")
      |> html_body(html(intro, url, button, outro))

    with {:ok, _metadata} <-
           Mailer.deliver(email, Application.get_env(:everyday_citizen, :mailer_overrides, [])) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      user.email,
      "Confirm your new email",
      {"To use this address for your Everyday Citizen account, open this link:", url,
       "Confirm this email", "If you didn't ask for this, you can ignore this email."}
    )
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(
      user.email,
      "Your sign-in link",
      {"Open this link to sign in to Everyday Citizen:", url, "Sign in",
       "The link works once and expires soon. If you didn't ask for it, you can ignore this email."}
    )
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(
      user.email,
      "Confirm your account",
      {"Open this link to confirm your Everyday Citizen account and sign in:", url,
       "Confirm and sign in",
       "If you didn't ask for an account, you can ignore this email; it stays unconfirmed and can't be used."}
    )
  end

  defp html(intro, url, button, outro) do
    url = escape(url)

    """
    <!doctype html>
    <html><body style="margin:0;padding:24px;background:#f4f5f6;font-family:-apple-system,Segoe UI,Helvetica,Arial,sans-serif;color:#15171a">
    <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #dadde1;border-radius:12px;padding:24px">
    <p style="margin:0 0 16px;font-size:18px;font-weight:700">Everyday Citizen</p>
    <p style="margin:0 0 20px;font-size:16px">#{escape(intro)}</p>
    <p style="margin:0 0 20px"><a href="#{url}" style="display:inline-block;padding:12px 20px;border-radius:10px;background:#15171a;color:#fff;font-weight:600;text-decoration:none">#{escape(button)}</a></p>
    <p style="margin:0 0 12px;font-size:13px;color:#4a5058;word-break:break-all">Or paste this into your browser: #{url}</p>
    <p style="margin:0;font-size:13px;color:#4a5058">#{escape(outro)}</p>
    </div></body></html>
    """
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
