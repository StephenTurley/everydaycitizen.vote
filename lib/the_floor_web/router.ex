defmodule TheFloorWeb.Router do
  use TheFloorWeb, :router

  import TheFloorWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TheFloorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TheFloorWeb do
    pipe_through :browser

    get "/district/:district", DistrictController, :show
    post "/district", DistrictController, :create
    # "Follow" while signed out: remember the page, then sign in
    get "/users/sign-in-to", UserSessionController, :sign_in_to
  end

  # Other scopes may use custom stacks.
  # scope "/api", TheFloorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:the_floor, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TheFloorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", TheFloorWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{TheFloorWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end
  end

  scope "/", TheFloorWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{TheFloorWeb.UserAuth, :mount_current_scope}] do
      # public pages: they work signed out and know who is signed in
      live "/", HomeLive
      live "/reps/:district", RepsLive
      live "/bills/:id", BillLive
      live "/this-week", ThisWeekLive

      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
