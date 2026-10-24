defmodule EverydayCitizenWeb.FeedbackLive do
  @moduledoc "Send feedback about the site (linked from every page's footer)."
  use EverydayCitizenWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Send feedback",
       remote_ip: EverydayCitizenWeb.RemoteIp.from_socket(socket)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="pt-6 flex flex-col gap-3">
        <h1 class="m-0 text-[24px] font-bold">Send feedback</h1>
        <p class="m-0 text-[15px] text-floor-muted">
          Something wrong, confusing or missing? Tell us. No account needed.
        </p>
        <.live_component
          module={EverydayCitizenWeb.FeedbackForm}
          id="feedback-site"
          open
          report={
            %{
              kind: "site",
              page: "/feedback",
              user: @current_scope && @current_scope.user,
              remote_ip: @remote_ip
            }
          }
        />
      </section>
    </Layouts.app>
    """
  end
end
