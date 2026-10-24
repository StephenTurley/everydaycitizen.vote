defmodule EverydayCitizenWeb.UnsubscribeHTML do
  @moduledoc "Pages for the daily email's unsubscribe link."
  use EverydayCitizenWeb, :html

  def confirm(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pt-10 flex flex-col gap-3">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">Stop the daily email?</h1>
        <p class="m-0 text-[15px] leading-relaxed text-floor-ink-2">
          You'll stop getting the email about the bills and reps you follow. You can turn it
          back on in your account.
        </p>
        <form method="post" action={~p"/unsubscribe/#{@token}"}>
          <button
            type="submit"
            class="mt-2 px-5 py-3 rounded-xl bg-floor-ink text-white text-[16px] font-semibold"
          >
            Stop the daily email
          </button>
        </form>
      </section>
    </Layouts.app>
    """
  end

  def done(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pt-10 flex flex-col gap-3">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">Done</h1>
        <p class="m-0 text-[15px] leading-relaxed text-floor-ink-2">
          You won't get the daily email anymore. You can turn it back on in your <.link
            navigate={~p"/users/settings"}
            class="font-semibold text-floor-accent"
          >account</.link>.
        </p>
      </section>
    </Layouts.app>
    """
  end

  def invalid(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pt-10 flex flex-col gap-3">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">
          This link doesn't work
        </h1>
        <p class="m-0 text-[15px] leading-relaxed text-floor-ink-2">
          You can turn the daily email off in your <.link
            navigate={~p"/users/settings"}
            class="font-semibold text-floor-accent"
          >account</.link>.
        </p>
      </section>
    </Layouts.app>
    """
  end
end
