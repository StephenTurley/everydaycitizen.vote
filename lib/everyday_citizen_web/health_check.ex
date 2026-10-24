defmodule EverydayCitizenWeb.HealthCheck do
  @moduledoc """
  Health endpoints for Fly's checks (fly.toml, docs/ops/deploys.md). `GET` or
  `HEAD`:

    * `/health` — liveness: `200 ok` whenever the endpoint is serving. It never
      touches the database. Fly's proxy routes traffic by this check, so a busy
      connection pool must not take the only machine out of rotation.

    * `/health/ready` — readiness: `200 ok` once the app has booted (the
      endpoint starts last, after the Repo and Oban) and the
      database answers `SELECT 1`, else `503 unavailable`. A top-level Fly check
      calls it. It doesn't affect routing, but a blue-green deploy waits for it
      before moving traffic to the new machine.

  Bodies never say more than `ok` or `unavailable`. The plug sits at the top of
  the endpoint, so it runs without a session, cookies, CSRF or request logging
  (Fly calls these every 10 seconds).
  """
  @behaviour Plug

  import Plug.Conn

  require Logger

  @query_timeout 2_000

  @impl true
  def init(opts), do: Keyword.get(opts, :repo, EverydayCitizen.Repo)

  @impl true
  def call(%Plug.Conn{method: method, path_info: ["health"]} = conn, _repo)
      when method in ["GET", "HEAD"],
      do: respond(conn, true)

  def call(%Plug.Conn{method: method, path_info: ["health", "ready"]} = conn, repo)
      when method in ["GET", "HEAD"],
      do: respond(conn, database_answers?(repo))

  def call(conn, _repo), do: conn

  defp respond(conn, healthy?) do
    {status, body} = if healthy?, do: {200, "ok"}, else: {503, "unavailable"}

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
    |> halt()
  end

  defp database_answers?(repo) do
    case repo.query("SELECT 1", [], timeout: @query_timeout) do
      {:ok, _} -> true
      {:error, error} -> down(error)
    end
  rescue
    error -> down(error)
  catch
    :exit, reason -> down(reason)
  end

  defp down(reason) do
    Logger.warning("health check: database did not answer: #{inspect(reason)}")
    false
  end
end
