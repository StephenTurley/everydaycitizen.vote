defmodule EverydayCitizenWeb.FollowToggle do
  @moduledoc """
  The `toggle_follow` event shared by pages with a follow button: flips the
  follow for the signed-in person, sets `:following`, and when their daily
  email is off says so (following is how the email knows what to send).
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias EverydayCitizen.Follows

  @spec toggle(Phoenix.LiveView.Socket.t(), Follows.target()) :: Phoenix.LiveView.Socket.t()
  def toggle(%{assigns: %{current_scope: %{user: %{} = user} = scope}} = socket, target) do
    if Follows.following?(scope, target) do
      :ok = Follows.unfollow(scope, target)
      assign(socket, :following, false)
    else
      {:ok, _} = Follows.follow(scope, target)

      socket
      |> assign(:following, true)
      |> then(&if(user.digest_enabled, do: &1, else: put_flash(&1, :info, digest_off())))
    end
  end

  def toggle(socket, _target), do: socket

  defp digest_off,
    do:
      "Following. Your daily email is off, so changes won't be emailed; turn it on in your account."
end
