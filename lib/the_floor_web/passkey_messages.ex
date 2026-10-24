defmodule TheFloorWeb.PasskeyMessages do
  @moduledoc """
  What to tell people when a passkey does not work. The browser reports a
  DOMException name; these messages never use WebAuthn jargon.
  """

  @doc "Message for a browser-side failure, by DOMException name."
  def client_error(name) when name in ["NotAllowedError", "AbortError"],
    do: "The passkey was cancelled or timed out. Try again when you're ready."

  def client_error("InvalidStateError"),
    do: "This device already has a passkey for your account. You can sign in with it."

  def client_error(_name), do: failed()

  @doc "Message for a response the server could not verify, or a lost challenge."
  def failed, do: "That didn't work. Please try again."

  @doc "Message for a passkey sign-in that was not accepted (the same for every cause)."
  def rejected, do: "We couldn't sign you in with that passkey. Try again, or use your email."
end
