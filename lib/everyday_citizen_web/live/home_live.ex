defmodule EverydayCitizenWeb.HomeLive do
  @moduledoc """
  The home page, news first: the laws signed most recently (each with its
  plain-English summary, see `AiBillSummary`), what is coming up for a vote,
  and the visitor's reps when their district is known, otherwise the finder.

  Finding a visitor's district: a ZIP code first; if it is split between
  districts, the street too; if it is unknown, the full address. Neither the ZIP
  code nor the address is stored, logged or put in a URL: they travel over the
  live socket (or a POST before it connects) to the lookup, and the browser then
  goes to `/district/:key`, which only ever carries the district.
  """
  use EverydayCitizenWeb, :live_view

  alias EverydayCitizen.{Legislation, Reps, Summaries}
  alias EverydayCitizen.Summaries.{Claude, Inputs}
  alias EverydayCitizenWeb.AiBillSummary

  @repo_url "https://github.com/StephenTurley/everydaycitizen.vote/blob/main/"
  @zone "America/New_York"
  @page 5

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "New laws and your representatives",
       district: session["district"],
       remote_ip: EverydayCitizenWeb.RemoteIp.from_socket(socket),
       crawler: EverydayCitizenWeb.Crawler.crawler?(socket),
       laws: [],
       more_laws: false,
       summaries: %{},
       upcoming: EverydayCitizen.Calendar.upcoming_floor(@page),
       step: :zip,
       zip: nil,
       split: [],
       error: nil,
       value: ""
     )
     |> load_laws()}
  end

  # The next page of laws, each with its summary; one more is read to know
  # whether there are more, and laws already shown (one signed since the page
  # opened shifts the rest down) are not added twice.
  defp load_laws(socket) do
    shown = MapSet.new(socket.assigns.laws, & &1.bill.id)
    page = Legislation.recent_laws(@page + 1, length(socket.assigns.laws))
    laws = page |> Enum.take(@page) |> Enum.reject(&MapSet.member?(shown, &1.bill.id))

    assign(socket,
      laws: socket.assigns.laws ++ laws,
      more_laws: length(page) > @page,
      summaries: Map.merge(socket.assigns.summaries, summaries(socket, Enum.map(laws, & &1.bill)))
    )
  end

  # None on the first page load. Once live: cached ones found by subject and
  # prompt version in one query, without reading the bills' text (a subject
  # names a version, whose text does not change); for the rest, the bill
  # page's path, which reads the text, applies the limits and asks for one
  # (never for crawlers).
  defp summaries(socket, bills) do
    if connected?(socket) and Claude.enabled?() do
      subjects = Inputs.bill_subjects(Enum.map(bills, & &1.id))
      cached = Summaries.cached_ai(:bill, Map.values(subjects))

      for bill <- bills,
          subject = subjects[bill.id],
          summary = summary(socket, bill, subject, cached[subject]),
          into: %{},
          do: {bill.id, summary}
    else
      %{}
    end
  end

  defp summary(_socket, _bill, subject, %{summary: text}), do: {subject, {:ok, text}}
  defp summary(%{assigns: %{crawler: true}}, _bill, _subject, nil), do: nil
  defp summary(socket, bill, _subject, nil), do: AiBillSummary.load(socket, bill)

  @impl true
  def handle_info({:ai_summary, "bill", subject, result}, socket) do
    summaries =
      Map.new(socket.assigns.summaries, fn
        {id, {^subject, _state}} -> {id, {subject, AiBillSummary.result_state(result)}}
        other -> other
      end)

    {:noreply, assign(socket, :summaries, summaries)}
  end

  @impl true
  def handle_event("more_laws", _params, socket), do: {:noreply, load_laws(socket)}

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

  defp day(%DateTime{} = at), do: at |> DateTime.shift_zone!(@zone) |> Calendar.strftime("%b %-d")

  defp weekday(%DateTime{} = at),
    do: at |> DateTime.shift_zone!(@zone) |> Calendar.strftime("%a, %b %-d")

  # the next floor event, unless it is already listed
  defp next_line(%{items: items, next: next}) do
    if next && next.id not in Enum.map(items, & &1.id),
      do: "Next on the calendar: #{day(next.start_at)}, #{next.title}"
  end

  # What a "Report a problem" form under a law's summary sends with the report.
  # a written summary's story, if it has one
  defp law_story({_subject, {:ok, text}}), do: story_of(text)

  defp law_story(_summary), do: nil

  defp report(assigns, subject) do
    %{
      kind: "bill",
      subject: subject,
      prompt_version: Summaries.cache_version(:bill),
      page: "/",
      user: assigns.current_scope && assigns.current_scope.user,
      remote_ip: assigns.remote_ip
    }
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, prompt_url: @repo_url <> Claude.prompt_path(:bill))

    ~H"""
    <Layouts.app flash={@flash} width={:full} current_scope={@current_scope}>
      <h1 class="sr-only">New laws and your representatives</h1>
      <%!-- Phones, one column: your reps (when known), new laws, coming up,
           then the finder (when not). Large screens: new laws in a 640px column,
           a sticky sidebar with your reps or the finder, then coming up. --%>
      <div class="flex flex-col gap-7 pt-5 pb-8 lg:grid lg:grid-cols-[minmax(0,640px)_320px] lg:justify-center lg:gap-x-12 lg:pt-8 lg:items-start">
        <aside class="contents lg:flex lg:flex-col lg:gap-6 lg:sticky lg:top-4 lg:col-start-2 lg:row-start-1">
          <.card
            :if={@district}
            id="your-reps"
            class="order-1 lg:order-1 !border-2 !border-floor-accent !px-4 !py-3 flex items-center justify-between gap-3"
          >
            <div class="flex flex-col min-w-0">
              <span class="text-[16px] font-bold">Your reps</span>
              <span class="text-[13px] text-floor-muted">
                {Reps.district_label(@district) || @district}
              </span>
            </div>
            <.link
              navigate={~p"/reps/#{@district}"}
              class="py-1 text-[15px] font-bold text-floor-accent whitespace-nowrap"
            >
              See their week ›
            </.link>
          </.card>

          <.card :if={!@district} id="finder" class="order-4 lg:order-1 flex flex-col gap-2">
            <.finder step={@step} zip={@zip} split={@split} error={@error} value={@value} />
          </.card>

          <section
            id="coming-up"
            aria-labelledby="coming-up-heading"
            class="order-3 lg:order-2 flex flex-col gap-2.5"
          >
            <h2 id="coming-up-heading" class="m-0 text-[20px] font-bold tracking-tight">
              Coming up for a vote
            </h2>
            <ul :if={@upcoming.items != []} class="m-0 p-0 list-none flex flex-col gap-2">
              <li :for={event <- @upcoming.items}>
                <.card class="!p-3.5 flex flex-col gap-1">
                  <p class="m-0 text-[13px] text-floor-muted">
                    {weekday(event.start_at)}<span :if={event.body}> · {event.body.name}</span>
                  </p>
                  <p :if={event.title} class="m-0 text-[15px] leading-snug">{event.title}</p>
                  <ul class="m-0 p-0 list-none flex flex-col gap-1">
                    <li :for={%{bill: bill} <- event.event_bills} class="text-[15px] leading-snug">
                      <.link
                        navigate={~p"/bills/#{bill.external_id}"}
                        class="font-semibold text-floor-accent hover:underline"
                      >
                        {bill.identifier}
                      </.link>
                      <span :if={bill.title} class="text-floor-ink-2">{bill.title}</span>
                    </li>
                  </ul>
                </.card>
              </li>
            </ul>
            <p
              :if={@upcoming.items == []}
              class="m-0 px-3.5 py-3 rounded-xl border border-dashed border-floor-line bg-floor-card text-[15px] text-floor-ink-2"
            >
              No votes are scheduled yet.
            </p>
            <p :if={line = next_line(@upcoming)} class="m-0 text-[14px] text-floor-muted">{line}</p>
            <.link
              navigate={~p"/this-week"}
              class="self-start py-1 text-[14px] font-semibold text-floor-accent"
            >
              This week's schedule ›
            </.link>
          </section>
        </aside>

        <section
          aria-labelledby="new-laws-heading"
          class="order-2 lg:col-start-1 lg:row-start-1 flex flex-col gap-2.5 lg:gap-3"
        >
          <div class="flex flex-col gap-0.5">
            <h2 id="new-laws-heading" class="m-0 text-[22px] lg:text-[30px] font-bold tracking-tight">
              New laws
            </h2>
            <p class="m-0 text-[14px] text-floor-muted">Signed most recently</p>
          </div>
          <.card
            :for={%{bill: bill, date: date} <- @laws}
            id={"law-#{bill.external_id}"}
            class="!p-3.5 lg:!px-5 lg:!py-4 flex flex-col gap-1.5"
          >
            <p class="m-0 text-[13px] text-floor-muted flex flex-wrap gap-x-2">
              <span class="font-bold text-floor-accent">Became law</span>
              <span>{Calendar.strftime(date, "%b %-d")}</span>
              <span>{bill.identifier}</span>
            </p>
            <.link
              navigate={~p"/bills/#{bill.external_id}"}
              class="text-[16px] lg:text-[18px] font-semibold leading-snug text-floor-accent hover:underline"
            >
              {bill.title || bill.identifier}
            </.link>
            <.story_line
              :if={story = law_story(@summaries[bill.id])}
              id={"law-summary-#{bill.external_id}"}
              class="mt-1"
              group={hd(story.groups)}
              more={length(story.groups) - 1}
              tags={story.tags}
              href={~p"/bills/#{bill.external_id}"}
              prompt_url={@prompt_url}
              report={report(assigns, elem(@summaries[bill.id], 0))}
              text={elem(elem(@summaries[bill.id], 1), 1)}
            />
            <.ai_box
              :if={(summary = @summaries[bill.id]) && !law_story(summary)}
              id={"law-summary-#{bill.external_id}"}
              class="mt-1 !py-2.5"
              title="In plain English"
              source="the bill"
              state={elem(summary, 1)}
              prompt_url={@prompt_url}
              report={report(assigns, elem(summary, 0))}
              clamp
            />
          </.card>
          <button
            :if={@more_laws}
            type="button"
            phx-click="more_laws"
            class="self-start py-2 text-[15px] font-semibold text-floor-accent"
          >
            Show 5 more
          </button>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :step, :atom, required: true
  attr :zip, :string, default: nil
  attr :split, :list, default: []
  attr :error, :string, default: nil
  attr :value, :string, default: ""

  # Every form: method/action so that before the live connection is up it is a
  # plain POST, never a GET that would put the ZIP or address in a URL.
  defp finder(assigns) do
    ~H"""
    <form
      :if={@step == :zip}
      id="zip-form"
      method="post"
      action={~p"/district"}
      phx-submit="zip"
      class="flex flex-col gap-2"
    >
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <label for="zip" class="text-[13px] font-semibold text-floor-muted">
        See what your own representatives did: your ZIP code
      </label>
      <div class="flex flex-col gap-2">
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
        <.submit label="Find my representatives" />
      </div>
      <.find_error error={@error} />
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

    <p class="m-0 text-[13px] text-floor-muted">
      Your ZIP code and address are used once to find your district. They are not saved.
    </p>
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
