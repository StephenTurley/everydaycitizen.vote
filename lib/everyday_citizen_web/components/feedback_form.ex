defmodule EverydayCitizenWeb.FeedbackForm do
  @moduledoc """
  "Report a problem" under an AI summary (or the site feedback form, opened
  from the start): a reason and an optional note, sent as a
  `EverydayCitizen.Feedback` report with what the reader was shown. No login
  needed. Five reports an hour per visitor; a filled-in hidden field (a bot)
  is thanked and dropped.
  """
  use EverydayCitizenWeb, :live_component

  alias EverydayCitizen.{Feedback, RateLimit}

  @limit 5
  @hour :timer.hours(1)
  @reasons [
    {"inaccurate", "It's inaccurate"},
    {"unclear", "It's unclear"},
    {"missing", "It leaves out something important"},
    {"one_sided", "It's one-sided"},
    {"other", "Something else"}
  ]

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:open, fn -> false end)
     |> assign_new(:state, fn -> if assigns[:open], do: :open, else: :closed end)
     |> assign_new(:error, fn -> nil end)}
  end

  @impl true
  def handle_event("open", _params, socket), do: {:noreply, assign(socket, state: :open)}
  def handle_event("cancel", _params, socket), do: {:noreply, assign(socket, state: :closed)}

  def handle_event("send", %{"report" => params}, socket) do
    cond do
      params["website"] not in [nil, ""] ->
        {:noreply, assign(socket, state: :sent)}

      RateLimit.hit({:feedback, socket.assigns.report.remote_ip}, @limit, @hour) == :limited ->
        {:noreply, assign(socket, state: :limited)}

      true ->
        submit(socket, Map.take(params, ["reason", "note"]))
    end
  end

  defp submit(socket, params) do
    report = socket.assigns.report

    attrs =
      report
      |> Map.take([:kind, :subject, :prompt_version, :summary, :page])
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(params)

    case Feedback.submit(attrs, report[:user]) do
      {:ok, _} -> {:noreply, assign(socket, state: :sent, error: nil)}
      {:error, _} -> {:noreply, assign(socket, error: "Please choose what's wrong.")}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :reasons, @reasons)

    ~H"""
    <div id={@id} class="text-[13px]">
      <%= case @state do %>
        <% :closed -> %>
          <button
            type="button"
            phx-click="open"
            phx-target={@myself}
            class="py-1 text-floor-muted underline"
          >
            Report a problem
          </button>
        <% :open -> %>
          <form
            phx-submit="send"
            phx-target={@myself}
            class="mt-1 flex flex-col gap-2 text-[14px] text-floor-ink"
          >
            <fieldset class="m-0 p-0 border-0 flex flex-col gap-1">
              <legend class="mb-1 font-semibold">What's wrong?</legend>
              <label :for={{value, label} <- @reasons} class="flex items-center gap-2 py-1">
                <input type="radio" name="report[reason]" value={value} /> {label}
              </label>
            </fieldset>
            <label class="flex flex-col gap-1">
              <span class="font-semibold">Anything to add? (optional)</span>
              <textarea
                name="report[note]"
                maxlength="1000"
                rows="3"
                class="px-3 py-2 rounded-lg border border-floor-line bg-floor-card text-[15px]"
              ></textarea>
            </label>
            <div class="hidden" aria-hidden="true">
              <input type="text" name="report[website]" tabindex="-1" autocomplete="off" />
            </div>
            <p :if={@error} class="m-0 text-red-700">{@error}</p>
            <div class="flex gap-2">
              <button
                type="submit"
                class="px-4 py-2 rounded-xl bg-floor-ink text-white font-semibold"
              >
                Send
              </button>
              <button
                :if={!@open}
                type="button"
                phx-click="cancel"
                phx-target={@myself}
                class="px-4 py-2 rounded-xl border border-floor-line font-semibold"
              >
                Cancel
              </button>
            </div>
          </form>
        <% :sent -> %>
          <p class="m-0 py-1 text-floor-muted">Thanks — we'll review it.</p>
        <% :limited -> %>
          <p class="m-0 py-1 text-floor-muted">
            You've sent several reports; please try again later.
          </p>
      <% end %>
    </div>
    """
  end
end
