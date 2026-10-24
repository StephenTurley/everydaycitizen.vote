defmodule EverydayCitizen.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EverydayCitizenWeb.Telemetry,
      EverydayCitizen.Repo,
      EverydayCitizen.RateLimit,
      EverydayCitizen.Adapters.Federal.Supervisor,
      {Oban, Application.fetch_env!(:everyday_citizen, Oban)},
      # Releases jobs the previous deploy left executing (production only)
      rescue_orphans(),
      {DNSCluster, query: Application.get_env(:everyday_citizen, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EverydayCitizen.PubSub},
      # Start a worker by calling: EverydayCitizen.Worker.start_link(arg)
      # {EverydayCitizen.Worker, arg},
      # Start to serve requests, typically the last entry
      EverydayCitizenWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EverydayCitizen.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  defp rescue_orphans do
    if Application.get_env(:everyday_citizen, :rescue_orphaned_jobs, false) do
      Supervisor.child_spec(
        {Task, fn -> EverydayCitizen.ObanRescue.rescue_orphans(Oban.config().node) end},
        id: :rescue_orphaned_jobs
      )
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EverydayCitizenWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
