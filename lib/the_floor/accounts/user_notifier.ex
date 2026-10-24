defmodule TheFloor.Accounts.UserNotifier do
  @moduledoc "Account emails: sign-in links and email-change confirmations."
  import Swoosh.Email

  alias TheFloor.Accounts.User
  alias TheFloor.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(Application.fetch_env!(:the_floor, :mail_from))
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <-
           Mailer.deliver(email, Application.get_env(:the_floor, :mailer_overrides, [])) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirm your new email", """
    To use this address for your Everyday Citizen account, open this link:

    #{url}

    If you didn't ask for this, you can ignore this email.
    """)
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
    deliver(user.email, "Your sign-in link", """
    Open this link to sign in to Everyday Citizen:

    #{url}

    The link works once and expires soon. If you didn't ask for it, you can
    ignore this email.
    """)
  end

  defp deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your account", """
    Open this link to confirm your Everyday Citizen account and sign in:

    #{url}

    If you didn't ask for an account, you can ignore this email; it stays
    unconfirmed and can't be used.
    """)
  end
end
