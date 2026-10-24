import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/the_floor start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
# Failed jobs to Sentry: a transient source failure only once its last retry
# fails (TheFloor.SentryJobs). A function, so it lives here, not in config.exs.
config :sentry,
  integrations: [oban: [should_report_error_callback: &TheFloor.SentryJobs.report_error?/2]]

if System.get_env("PHX_SERVER") do
  config :the_floor, TheFloorWeb.Endpoint, server: true
end

config :the_floor, TheFloorWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# Congress.gov API key. Test config sets a dummy; nil is allowed in dev.
if config_env() != :test do
  config :the_floor, :congress_gov_api_key, System.get_env("CONGRESS_GOV_API_KEY")
end

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :the_floor, TheFloorWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/the_floor_web/router\.ex$",
        ~r"lib/the_floor_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # Oban's node names the machine and the deploy's image, so a deploy's jobs are
  # told apart from the previous deploy's, which TheFloor.ObanRescue releases at
  # boot. (The release node name stays the machine id, for `rpc` and ssh.)
  image_tag =
    case String.split(System.get_env("FLY_IMAGE_REF", ""), ":") do
      [_, tag] -> tag
      _ -> "local"
    end

  config :the_floor, Oban, node: "#{System.get_env("FLY_MACHINE_ID", "machine")}-#{image_tag}"
  config :the_floor, :rescue_orphaned_jobs, true

  # The deploy labels the image with the commit (`--image-label git-<sha>`), so
  # each Sentry event names the release that produced it.
  release_sha =
    case Regex.run(~r/:git-([0-9a-f]+)$/, System.get_env("FLY_IMAGE_REF", "")) do
      [_, sha] -> sha
      _ -> nil
    end

  # Errors, crashes (the logger handler; no log messages) and failed jobs.
  config :sentry,
    dsn: System.get_env("SENTRY_DSN"),
    release: release_sha && "the-floor@" <> release_sha,
    logs: []

  System.get_env("CONGRESS_GOV_API_KEY") ||
    raise "environment variable CONGRESS_GOV_API_KEY is missing."

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :the_floor, TheFloor.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # Passkeys are bound to this RP ID forever: changing it orphans every
  # registered passkey. PHX_HOST is everydaycitizen.vote.
  config :the_floor, :webauthn,
    origin: "https://#{host}",
    rp_id: host,
    rp_name: "Everyday Citizen"

  # Every other host redirects here (TheFloorWeb.CanonicalHost).
  config :the_floor, :canonical_host, host

  config :the_floor, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :the_floor, TheFloorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :the_floor, TheFloorWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :the_floor, TheFloorWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Email (sign-in links, the daily email) goes through Resend; the domain is
  # verified there. Required: without it no one could sign in.
  config :the_floor, TheFloor.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key:
      System.get_env("RESEND_API_KEY") ||
        raise("environment variable RESEND_API_KEY is missing.")
end
