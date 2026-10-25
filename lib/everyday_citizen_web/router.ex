defmodule EverydayCitizenWeb.Router do
  use EverydayCitizenWeb, :router

  import EverydayCitizenWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EverydayCitizenWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # The daily email's unsubscribe link: the signed token is the credential, and
  # a mail program's one-click POST carries no CSRF token.
  pipeline :mail_link do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EverydayCitizenWeb.Layouts, :root}
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EverydayCitizenWeb do
    pipe_through :browser

    get "/district/:district", DistrictController, :show
    post "/district", DistrictController, :create
    # "Follow" while signed out: remember the page, then sign in
    get "/users/sign-in-to", UserSessionController, :sign_in_to
  end

  scope "/", EverydayCitizenWeb do
    pipe_through :mail_link

    get "/unsubscribe/:token", UnsubscribeController, :show
    post "/unsubscribe/:token", UnsubscribeController, :delete
  end

  # Other scopes may use custom stacks.
  # scope "/api", EverydayCitizenWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:everyday_citizen, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EverydayCitizenWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", EverydayCitizenWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{EverydayCitizenWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", EverydayCitizenWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{EverydayCitizenWeb.UserAuth, :mount_current_scope}] do
      # public pages: they work signed out and know who is signed in
      live "/", HomeLive
      live "/reps/:district", RepsLive
      live "/bills/:id", BillLive
      live "/people/:id", PersonLive
      live "/this-week", ThisWeekLive
      live "/feedback", FeedbackLive

      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
