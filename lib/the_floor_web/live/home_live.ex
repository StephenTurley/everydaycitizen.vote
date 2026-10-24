defmodule TheFloorWeb.HomeLive do
  @moduledoc """
  Entering an address. The address travels only over the live socket to the
  lookup; on success the browser goes to `/district/:key`, so URLs, logs and the
  session only ever carry the district.
  """
  use TheFloorWeb, :live_view

  alias TheFloor.Reps

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Find your representatives",
       district: session["district"],
       form: to_form(%{"address" => ""}),
       error: nil
     )}
  end

  @impl true
  def handle_event("find", %{"address" => address}, socket) do
    case Reps.find(String.trim(address)) do
      {:ok, district, _reps} ->
        {:noreply, redirect(socket, to: ~p"/district/#{district}")}

      {:error, reason} ->
        {:noreply, assign(socket, form: to_form(%{"address" => address}), error: message(reason))}
    end
  end

  defp message(:not_found), do: "We couldn't find that address. Check the street and ZIP code."
  defp message(:unavailable), do: "Address lookup is unavailable right now. Please try again."

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

      <.form for={@form} id="address-form" phx-submit="find" class="flex flex-col gap-2">
        <label for="address" class="text-[13px] font-semibold text-floor-muted">Your address</label>
        <input
          type="text"
          id="address"
          name="address"
          value={@form[:address].value}
          autocomplete="street-address"
          placeholder="Street, city, state, ZIP"
          class="text-[16px] px-3 py-3 rounded-xl border border-[#b8bdc4] bg-floor-card"
          aria-describedby={if @error, do: "address-error"}
        />
        <p :if={@error} id="address-error" role="alert" class="m-0 text-[14px] text-floor-ink">
          {@error}
        </p>
        <button
          type="submit"
          class="mt-1 py-3 rounded-xl bg-floor-ink text-white text-[16px] font-semibold"
        >
          Find my representatives
        </button>
        <p class="m-0 text-[13px] text-floor-muted">
          Your address is used once to find your district. It is not saved.
        </p>
      </.form>
    </Layouts.app>
    """
  end
end
