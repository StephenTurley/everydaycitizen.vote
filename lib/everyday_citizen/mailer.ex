defmodule EverydayCitizen.Mailer do
  use Swoosh.Mailer, otp_app: :everyday_citizen

  @doc """
  Our From address, plus the Reply-To that replies go to when one is configured
  (`MAIL_REPLY_TO`: the From mailbox only forwards).
  """
  @spec sender(Swoosh.Email.t()) :: Swoosh.Email.t()
  def sender(email) do
    email = Swoosh.Email.from(email, Application.fetch_env!(:everyday_citizen, :mail_from))

    case Application.get_env(:everyday_citizen, :mail_reply_to) do
      nil -> email
      reply_to -> Swoosh.Email.reply_to(email, reply_to)
    end
  end
end
