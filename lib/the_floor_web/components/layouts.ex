defmodule TheFloorWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use TheFloorWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  The app shell: the header (name, "This week", "Change address") over a
  phone-width column.

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :wide, :boolean, default: false, doc: "allow a wider column on large screens"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="bg-floor-card border-b border-floor-line">
      <nav
        aria-label="Main"
        class="mx-auto max-w-3xl px-5 flex items-center justify-between gap-4"
      >
        <a href={~p"/"} class="py-4 text-[19px] font-bold tracking-tight text-floor-ink">
          The Floor
        </a>
        <div class="flex items-center gap-5 text-sm font-medium">
          <a href={~p"/this-week"} class="py-3 text-floor-accent hover:text-floor-accent-dark">
            This week
          </a>
          <a href={~p"/"} class="py-3 text-floor-accent hover:text-floor-accent-dark">
            Change address
          </a>
        </div>
      </nav>
    </header>

    <main class={["mx-auto px-5 pb-10", if(@wide, do: "max-w-3xl", else: "max-w-xl")]}>
      {render_slot(@inner_block)}
    </main>

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
