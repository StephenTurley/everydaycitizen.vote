import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :everyday_citizen, EverydayCitizen.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "the_floor_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :everyday_citizen, EverydayCitizenWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "vx/m6u/9SJpiE3a7J/RmURB1seCTqc+9dZThH2F9hlsS3fv3TXIQyhlLc9D0Biox",
  server: false

# In test we don't send emails
config :everyday_citizen, EverydayCitizen.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

config :everyday_citizen, Oban, testing: :manual

# The test endpoint listens on 4002; the software authenticator signs for this origin.
config :everyday_citizen, :webauthn,
  origin: "http://localhost:4002",
  rp_id: "localhost",
  rp_name: "Everyday Citizen"

# One bulk entry per chunk job, so tests exercise splitting
config :everyday_citizen, :bulk_chunk_size, 1

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Federal adapter: no rate limiting, no network, fast retries
config :everyday_citizen, :federal_rate_limits,
  congress_gov: 0,
  govinfo: 0,
  house_docs: 0,
  senate_gov: 0,
  voteview: 0,
  census: 0

config :everyday_citizen, :congress_gov_api_key, "test-key"

config :everyday_citizen, :anthropic_req_options,
  plug: {Req.Test, EverydayCitizen.Claude},
  retry: false

config :everyday_citizen, :anthropic_api_key, "test-anthropic-key"

config :everyday_citizen, :federal_req_options,
  plug: {Req.Test, EverydayCitizen.Federal},
  retry_delay: 0,
  retry_log_level: false
