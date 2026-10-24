# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :the_floor,
  ecto_repos: [TheFloor.Repo],
  generators: [timestamp_type: :utc_datetime]

# Time zone database (Senate vote times are America/New_York)
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure the endpoint
config :the_floor, TheFloorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TheFloorWeb.ErrorHTML, json: TheFloorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TheFloor.PubSub,
  live_view: [signing_salt: "baKeoOiE"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :the_floor, TheFloor.Mailer, adapter: Swoosh.Adapters.Local

config :the_floor, Oban,
  repo: TheFloor.Repo,
  # bulk: the first-run bulk load's chunk jobs (Federal.BulkBatch)
  queues: [ingest: 4, text: 2, bulk: 4],
  plugins: [
    # Rescue jobs left executing by a crashed node; prune finished jobs after a week.
    # rescue_after must exceed every worker's timeout (the bulk bill and text
    # backfills allow 90 minutes), or a still-running job would be started twice.
    {Oban.Plugins.Lifeline, rescue_after: :timer.hours(2)},
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     timezone: "America/New_York",
     crontab: [
       {"0 2 * * *", TheFloor.Adapters.Federal.Jobs.SyncCongress},
       {"10 2 * * *", TheFloor.Adapters.Federal.Jobs.SyncMembers},
       {"30 2 * * *", TheFloor.Adapters.Federal.Jobs.SyncBills},
       {"40 2 * * *", TheFloor.Adapters.Federal.Jobs.SyncHouseVotes},
       {"40 2 * * *", TheFloor.Adapters.Federal.Jobs.SyncSenateVotes},
       {"50 2 * * *", TheFloor.Adapters.Federal.Jobs.SyncCommitteeMeetings},
       {"0 3 * * *", TheFloor.Adapters.Federal.Jobs.SyncHouseFloor},
       {"0 3 * * *", TheFloor.Adapters.Federal.Jobs.SyncSenateFloor},
       {"30 5 * * *", TheFloor.Adapters.Federal.Jobs.Relink},
       {"0 6 * * *", TheFloor.Adapters.Federal.Jobs.Coverage}
     ]}
  ]

# Adapters whose `all/0` lists their list-level ingest jobs as {name, worker, args}.
# Errors, crashes and failed jobs go to Sentry (inert without SENTRY_DSN).
# Oban: failed jobs become issues; scheduled (cron) jobs report each run to
# Sentry's Crons page, which flags a run that failed, ran long or never came.
config :sentry,
  integrations: [oban: [capture_errors: true, cron: [enabled: true]]],
  in_app_otp_apps: [:the_floor]

config :the_floor, :ingest_adapters, [TheFloor.Adapters.Federal.Jobs]

config :the_floor, :federal,
  congress: 119,
  # Census Geocoder geography vintage holding each congress's districts (the
  # current vintage already has the next congress's)
  census_vintages: %{119 => "ACS2025_Current"}

# The jurisdiction public pages show, and how each finds an address's seats.
config :the_floor, :default_jurisdiction, "federal"
config :the_floor, :locators, %{"federal" => TheFloor.Adapters.Federal.Geocoder}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  the_floor: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  the_floor: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# A visitor's address is used once to find their district and never stored or
# logged.
config :phoenix, :filter_parameters, ["password", "address"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
