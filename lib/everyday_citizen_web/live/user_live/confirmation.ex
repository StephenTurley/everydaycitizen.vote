defmodule EverydayCitizenWeb.UserLive.Confirmation do
  @moduledoc """
  The page an emailed sign-in link opens. One button signs in (and confirms a
  new account): the link is not used on page load, so mail scanners that open
  links do not spend it. Signing in keeps the person signed in on this device.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="pt-10 pb-4 flex flex-col gap-3">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">
          {if @user.confirmed_at, do: "Sign in", else: "Welcome"}
        </h1>
        <p class="m-0 text-[15px] leading-relaxed text-floor-ink-2">{@user.email}</p>
      </section>

      <.form
        for={@form}
        id={if @user.confirmed_at, do: "login_form", else: "confirmation_form"}
        phx-submit="submit"
        phx-mounted={JS.focus_first()}
        action={
          if @user.confirmed_at, do: ~p"/users/log-in", else: ~p"/users/log-in?_action=confirmed"
        }
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
        <input type="hidden" name={@form[:remember_me].name} value="true" />
        <button
          type="submit"
          phx-disable-with="Signing in…"
          class="w-full py-3 rounded-xl bg-floor-ink text-white text-[16px] font-semibold"
        >
          {if @user.confirmed_at, do: "Sign in", else: "Confirm and sign in"}
        </button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "That sign-in link is invalid or has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
