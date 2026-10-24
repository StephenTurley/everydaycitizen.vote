defmodule EverydayCitizenWeb.HealthCheckTest do
  use EverydayCitizenWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias EverydayCitizenWeb.HealthCheck

  defmodule DownRepo do
    def query(_sql, _params, _opts),
      do: {:error, %DBConnection.ConnectionError{message: "secret detail"}}
  end

  defmodule RaisingRepo do
    def query(_sql, _params, _opts), do: raise(DBConnection.ConnectionError, "secret detail")
  end

  defmodule ExitingRepo do
    def query(_sql, _params, _opts), do: exit(:timeout)
  end

  defmodule UntouchableRepo do
    def query(_sql, _params, _opts), do: raise("the liveness check must not query")
  end

  # Request logging (Phoenix.Logger) and metrics hang off Plug.Telemetry's
  # [:phoenix, :endpoint, :start] event. Report it to this test only: the
  # request runs in the test process.
  setup do
    test_pid = self()
    id = {__MODULE__, make_ref()}

    :telemetry.attach(
      id,
      [:phoenix, :endpoint, :start],
      fn _event, _measurements, %{conn: conn}, _ ->
        if self() == test_pid, do: send(test_pid, {:request_logged, conn.request_path})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(id) end)
  end

  for path <- ["/health", "/health/ready"] do
    describe "GET #{path}" do
      test "answers ok while the app is up", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert response(conn, 200) == "ok"
        assert response_content_type(conn, :text) =~ "text/plain"
        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end

      test "needs no session, sets no cookie and is not logged", %{conn: conn} do
        conn = get(conn, unquote(path))

        assert get_resp_header(conn, "set-cookie") == []
        refute Map.has_key?(conn.private, :plug_session)
        refute_received {:request_logged, _}
      end

      test "answers HEAD too", %{conn: conn} do
        assert head(conn, unquote(path)).status == 200
      end
    end
  end

  test "(control) an ordinary request is logged, so the check above means something",
       %{conn: conn} do
    get(conn, "/this-week")
    assert_received {:request_logged, "/this-week"}
  end

  test "/health never touches the database" do
    opts = HealthCheck.init(repo: UntouchableRepo)
    conn = HealthCheck.call(Plug.Test.conn(:get, "/health"), opts)

    assert conn.halted
    assert conn.status == 200
  end

  test "other paths and methods pass through untouched" do
    for conn <- [
          Plug.Test.conn(:get, "/healthz"),
          Plug.Test.conn(:get, "/health/other"),
          Plug.Test.conn(:post, "/health"),
          Plug.Test.conn(:post, "/health/ready")
        ] do
      refute HealthCheck.call(conn, HealthCheck.init(repo: UntouchableRepo)).halted
    end
  end

  for repo <- [DownRepo, RaisingRepo, ExitingRepo] do
    test "/health/ready answers 503 without details when the database does not (#{inspect(repo)})" do
      opts = HealthCheck.init(repo: unquote(repo))

      {conn, log} =
        with_log(fn -> HealthCheck.call(Plug.Test.conn(:get, "/health/ready"), opts) end)

      assert conn.halted
      assert conn.status == 503
      assert conn.resp_body == "unavailable"
      refute conn.resp_body =~ "secret"
      assert log =~ "health check: database did not answer"
    end
  end

  test "Fly's check on the machine's own address is answered, not sent to the canonical host",
       %{conn: conn} do
    Application.put_env(:everyday_citizen, :canonical_host, "everydaycitizen.vote")
    on_exit(fn -> Application.delete_env(:everyday_citizen, :canonical_host) end)

    conn = %{conn | host: "172.19.4.2"} |> get("/health/ready")
    assert response(conn, 200) == "ok"
  end
end
