defmodule TheFloorWeb.HomeLive do
  @moduledoc """
  Finding a visitor's district: a ZIP code first; if it is split between
  districts, the street too; if it is unknown, the full address. Neither the ZIP
  code nor the address is stored, logged or put in a URL: they travel over the
  live socket (or a POST before it connects) to the lookup, and the browser then
  goes to `/district/:key`, which only ever carries the district.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Reps

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Find your representatives",
       district: session["district"],
       step: :zip,
       zip: nil,
       split: [],
       error: nil,
       value: ""
     )}
  end

  @impl true
  def handle_event("zip", %{"zip" => zip}, socket) do
    zip = String.trim(zip)

    case valid_zip(zip) do
      {:ok, zip} -> {:noreply, by_zip(socket, zip, Reps.districts_for_postal_code(zip))}
      {:error, reason} -> {:noreply, assign(socket, error: message(reason), value: zip)}
    end
  end

  def handle_event("street", %{"street" => street}, socket) do
    lookup(socket, street, &"#{&1}, #{socket.assigns.zip}")
  end

  def handle_event("find", %{"address" => address}, socket), do: lookup(socket, address, & &1)

  def handle_event("full", _params, socket),
    do: {:noreply, assign(socket, step: :address, error: nil, value: "")}

  defp by_zip(socket, _zip, [district]), do: redirect(socket, to: ~p"/district/#{district}")

  defp by_zip(socket, zip, [_ | _] = split),
    do: assign(socket, step: :street, zip: zip, split: split, error: nil, value: "")

  defp by_zip(socket, _zip, []),
    do: assign(socket, step: :address, error: message(:unknown_zip), value: "")

  defp lookup(socket, typed, to_address) do
    with {:ok, trimmed} <- present(typed),
         {:ok, district, _reps} <- Reps.find(to_address.(trimmed)) do
      {:noreply, redirect(socket, to: ~p"/district/#{district}")}
    else
      {:error, reason} -> {:noreply, assign(socket, error: message(reason), value: typed)}
    end
  end

  @doc "A five-digit ZIP code, or `{:error, :bad_zip}`."
  def valid_zip(zip) when is_binary(zip) do
    if zip =~ ~r/^\d{5}$/, do: {:ok, zip}, else: {:error, :bad_zip}
  end

  def valid_zip(_), do: {:error, :bad_zip}

  @doc "The trimmed address, or `{:error, :blank}`."
  def present(address) when is_binary(address) do
    case String.trim(address) do
      "" -> {:error, :blank}
      trimmed -> {:ok, trimmed}
    end
  end

  def present(_), do: {:error, :blank}

  @doc "What to tell a visitor when finding their district did not work."
  def message(:blank), do: "Enter your address to find your representatives."
  def message(:bad_zip), do: "Enter a 5-digit ZIP code."
  def message(:unknown_zip), do: "We don't have that ZIP code. Enter your full address instead."

  def message(:split_zip),
    do: "Your ZIP code covers more than one district. Enter your full address."

  def message(:not_found), do: "We couldn't find that address. Check the street and ZIP code."
  def message(:unavailable), do: "Address lookup is unavailable right now. Please try again."

  defp split_text(zip, [a, b]), do: "ZIP code #{zip} is split between #{a} and #{b}."
  defp split_text(zip, many), do: "ZIP code #{zip} is split between #{Enum.join(many, ", ")}."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="pt-10 pb-6 flex flex-col gap-3">
        <h1 class="m-0 text-[28px] leading-tight font-bold tracking-tight">
          What are your representatives doing?
        </h1>
        <p class="m-0 text-[15px] leading-relaxed text-floor-ink-2">
          See how your senators and representative voted, what they introduced, and what
          they got changed, with every item linked to the official record.
        </p>
      </section>

      <.card :if={@district} class="mb-4">
        <a href={~p"/reps/#{@district}"} class="text-[15px] font-semibold text-floor-accent">
          Your reps ({@district}) ›
        </a>
      </.card>

      <%!-- Every form: method/action so that before the live connection is up it is
           a plain POST, never a GET that would put the ZIP or address in a URL --%>
      <form
        :if={@step == :zip}
        id="zip-form"
        method="post"
        action={~p"/district"}
        phx-submit="zip"
        class="flex flex-col gap-2"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <label for="zip" class="text-[13px] font-semibold text-floor-muted">Your ZIP code</label>
        <input
          type="text"
          id="zip"
          name="zip"
          value={@value}
          inputmode="numeric"
          autocomplete="postal-code"
          maxlength="5"
          placeholder="e.g. 52240"
          class="text-[16px] px-3 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card"
          aria-describedby={if @error, do: "find-error"}
        />
        <.find_error error={@error} />
        <.submit label="Find my representatives" />
        <button
          type="button"
          phx-click="full"
          class="self-start py-2 text-[14px] font-medium text-floor-accent"
        >
          Enter your full address instead
        </button>
      </form>

      <form
        :if={@step == :street}
        id="street-form"
        method="post"
        action={~p"/district"}
        phx-submit="street"
        class="flex flex-col gap-2"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <input type="hidden" name="zip" value={@zip} />
        <p class="m-0 text-[15px]">
          {split_text(@zip, @split)} Enter your street address to find yours.
        </p>
        <label for="street" class="text-[13px] font-semibold text-floor-muted">Street address</label>
        <input
          type="text"
          id="street"
          name="street"
          value={@value}
          autocomplete="address-line1"
          placeholder="e.g. 400 S Clinton St"
          class="text-[16px] px-3 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card"
          aria-describedby={if @error, do: "find-error"}
        />
        <.find_error error={@error} />
        <.submit label="Find my representatives" />
      </form>

      <form
        :if={@step == :address}
        id="address-form"
        method="post"
        action={~p"/district"}
        phx-submit="find"
        class="flex flex-col gap-2"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
        <label for="address" class="text-[13px] font-semibold text-floor-muted">Your address</label>
        <input
          type="text"
          id="address"
          name="address"
          value={@value}
          autocomplete="street-address"
          placeholder="Street, city, state, ZIP"
          class="text-[16px] px-3 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card"
          aria-describedby={if @error, do: "find-error"}
        />
        <.find_error error={@error} />
        <.submit label="Find my representatives" />
      </form>

      <p class="mt-2 text-[13px] text-floor-muted">
        Your ZIP code and address are used once to find your district. They are not saved.
      </p>
    </Layouts.app>
    """
  end

  attr :error, :string, default: nil

  defp find_error(assigns) do
    ~H"""
    <p :if={@error} id="find-error" role="alert" class="m-0 text-[14px] text-floor-ink">{@error}</p>
    """
  end

  attr :label, :string, required: true

  defp submit(assigns) do
    ~H"""
    <button
      type="submit"
      phx-disable-with="Looking up…"
      class="mt-1 py-3 rounded-xl bg-floor-ink text-white text-[16px] font-semibold"
    >
      {@label}
    </button>
    """
  end
end
