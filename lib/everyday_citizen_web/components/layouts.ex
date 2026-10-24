defmodule EverydayCitizenWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EverydayCitizenWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  The app shell: the header (name, "This week", "Sign in" or "Account") over a
  phone-width column, or with `width={:full}` a column that widens to 1280px on
  large screens for a page's desktop columns. The header always spans 1280px
  there, so every page lines up.

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :width, :atom, values: [:narrow, :full], default: :narrow
  attr :current_scope, :map, default: nil, doc: "the signed-in scope, if any"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="bg-floor-card border-b border-floor-line">
      <nav
        aria-label="Main"
        class="mx-auto max-w-3xl lg:max-w-[1280px] px-5 lg:px-10 flex flex-wrap items-center justify-between gap-x-3 sm:gap-x-4"
      >
        <a
          href={~p"/"}
          class="py-4 text-[17px] sm:text-[19px] font-bold tracking-tight whitespace-nowrap text-floor-ink"
        >
          Everyday Citizen
        </a>
        <div class="flex items-center gap-3 sm:gap-5 text-[13px] sm:text-sm font-medium whitespace-nowrap">
          <a href={~p"/this-week"} class="py-3 text-floor-accent hover:text-floor-accent-dark">
            This week
          </a>
          <.link
            :if={@current_scope && @current_scope.user}
            navigate={~p"/users/settings"}
            class="py-3 text-floor-accent hover:text-floor-accent-dark"
          >
            Account
          </.link>
          <.link
            :if={!(@current_scope && @current_scope.user)}
            navigate={~p"/users/log-in"}
            class="py-3 text-floor-accent hover:text-floor-accent-dark"
          >
            Sign in
          </.link>
        </div>
      </nav>
    </header>

    <main class={[
      "mx-auto px-5 pb-10 max-w-xl",
      @width == :full && "lg:max-w-[1280px] lg:px-10"
    ]}>
      {render_slot(@inner_block)}
    </main>

    <footer class={[
      "mx-auto px-5 pb-8 max-w-xl text-[13px] text-floor-muted",
      @width == :full && "lg:max-w-[1280px] lg:px-10"
    ]}>
      <.link navigate={~p"/feedback"} class="underline">Send feedback</.link>
    </footer>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
