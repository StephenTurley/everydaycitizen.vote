defmodule TheFloor.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TheFloorWeb.Telemetry,
      TheFloor.Repo,
      TheFloor.Adapters.Federal.Supervisor,
      {Oban, Application.fetch_env!(:the_floor, Oban)},
      {DNSCluster, query: Application.get_env(:the_floor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TheFloor.PubSub},
      # Start a worker by calling: TheFloor.Worker.start_link(arg)
      # {TheFloor.Worker, arg},
      # Start to serve requests, typically the last entry
      TheFloorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TheFloor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TheFloorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
