# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :everyday_citizen, :scopes,
  user: [
    default: true,
    module: EverydayCitizen.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: EverydayCitizen.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :everyday_citizen,
  ecto_repos: [EverydayCitizen.Repo],
  generators: [timestamp_type: :utc_datetime]

# Time zone database (Senate vote times are America/New_York)
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

# Configure the endpoint
config :everyday_citizen, EverydayCitizenWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: EverydayCitizenWeb.ErrorHTML, json: EverydayCitizenWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EverydayCitizen.PubSub,
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
config :everyday_citizen, EverydayCitizen.Mailer, adapter: Swoosh.Adapters.Local
config :everyday_citizen, :mail_from, {"Everyday Citizen", "hello@everydaycitizen.vote"}

# Plain-English section summaries (EverydayCitizen.Summaries): written on first
# view and cached; the prompt is priv/prompts/section_summary.<prompt_version>.md.
config :everyday_citizen, :summaries,
  model: "claude-haiku-5-5",
  prompt_versions: %{section: "v2", bill: "v1", bill_chunk: "v1", rep_week: "v1"},
  # new summaries pause once today's Claude spend reaches this (dollars)
  daily_budget_usd: 2.0,
  # dollars per million tokens; the long-prompt rates apply to a whole request
  # whose input exceeds long_prompt_tokens
  rates: %{
    input: 0.10,
    output: 0.50,
    long_input: 0.50,
    long_output: 2.50,
    long_prompt_tokens: 100_000
  }

# WebAuthn relying party (passkeys). Dev values; test.exs and runtime.exs (prod)
# override. The origin must match the browser's address bar exactly.
config :everyday_citizen, :webauthn,
  origin: "http://localhost:4000",
  rp_id: "localhost",
  rp_name: "Everyday Citizen"

config :everyday_citizen, Oban,
  # a deploy stops the old machine: running jobs get 25 s to finish
  shutdown_grace_period: :timer.seconds(25),
  repo: EverydayCitizen.Repo,
  # bulk: the first-run bulk load's chunk jobs (Federal.BulkBatch)
  queues: [ingest: 4, text: 2, bulk: 4, mail: 2, summaries: 2],
  plugins: [
    # Rescue jobs left executing by a crashed node; prune finished jobs after a week.
    # rescue_after must exceed every worker's timeout (the bulk bill and text
    # backfills allow 90 minutes), or a still-running job would be started twice.
    {Oban.Plugins.Lifeline, rescue_after: :timer.hours(2)},
    {Oban.Plugins.Pruner, max_age: 7 * 24 * 60 * 60},
    {Oban.Plugins.Cron,
     timezone: "America/New_York",
     crontab: [
       {"0 2 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncCongress},
       {"10 2 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncMembers},
       {"30 2 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncBills},
       {"40 2 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncHouseVotes},
       {"40 2 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncSenateVotes},
       {"50 2 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncCommitteeMeetings},
       {"0 3 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncHouseFloor},
       {"0 3 * * *", EverydayCitizen.Adapters.Federal.Jobs.SyncSenateFloor},
       {"30 5 * * *", EverydayCitizen.Adapters.Federal.Jobs.Relink},
       {"0 6 * * *", EverydayCitizen.Adapters.Federal.Jobs.Coverage},
       {"0 7 * * *", EverydayCitizen.Jobs.DigestScheduler}
     ]}
  ]

# Adapters whose `all/0` lists their list-level ingest jobs as {name, worker, args}.
# Errors, crashes and failed jobs go to Sentry (inert without SENTRY_DSN).
# Oban: failed jobs become issues. Only the coverage job reports its runs to
# Sentry's Crons page (EverydayCitizen.SentryCrons); the plan allows one monitor.
config :sentry,
  integrations: [oban: [capture_errors: true, cron: [enabled: false]]],
  in_app_otp_apps: [:everyday_citizen]

config :everyday_citizen, :ingest_adapters, [EverydayCitizen.Adapters.Federal.Jobs]

config :everyday_citizen, :federal,
  congress: 119,
  # Census Geocoder geography vintage holding each congress's districts (the
  # current vintage already has the next congress's)
  census_vintages: %{119 => "ACS2025_Current"}

# The jurisdiction public pages show, and how each finds an address's seats.
config :everyday_citizen, :default_jurisdiction, "federal"
config :everyday_citizen, :locators, %{"federal" => EverydayCitizen.Adapters.Federal.Geocoder}

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  everyday_citizen: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  everyday_citizen: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# A visitor's address is used once to find their district and never stored or
# logged.
config :phoenix, :filter_parameters, ["password", "address", "street", "zip"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
