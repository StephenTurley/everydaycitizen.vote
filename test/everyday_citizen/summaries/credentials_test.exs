defmodule EverydayCitizen.Summaries.CredentialsTest do
  # not async: credentials are global configuration and one cached token
  use ExUnit.Case, async: false

  alias EverydayCitizen.Summaries.{Claude, Credentials}

  @federation %{
    rule_id: "fdrl_test",
    organization_id: "org-uuid",
    service_account_id: "svac_test",
    workspace_id: "wrkspc_test",
    audience: "https://api.anthropic.com"
  }

  setup do
    previous_key = Application.get_env(:everyday_citizen, :anthropic_api_key)

    on_exit(fn ->
      Application.put_env(:everyday_citizen, :anthropic_api_key, previous_key)
      Application.delete_env(:everyday_citizen, :anthropic_federation)
      Credentials.reset()
    end)

    Credentials.reset()
    :ok
  end

  # the token cache makes the requests from its own process
  defp allow_cache do
    server = Process.whereis(Credentials)
    Req.Test.allow(EverydayCitizen.FlyOidc, self(), server)
    Req.Test.allow(EverydayCitizen.Claude, self(), server)
  end

  defp federate(expires_in \\ 600) do
    Application.put_env(:everyday_citizen, :anthropic_federation, @federation)
    test = self()
    counter = :counters.new(1, [])

    Req.Test.stub(EverydayCitizen.FlyOidc, fn conn ->
      :counters.add(counter, 1, 1)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:oidc, conn.request_path, Jason.decode!(body)})
      Plug.Conn.send_resp(conn, 200, "jwt-#{:counters.get(counter, 1)}")
    end)

    Req.Test.stub(EverydayCitizen.Claude, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:exchange, conn.request_path, Jason.decode!(body)})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(
        200,
        Jason.encode!(%{
          "access_token" => "sk-ant-oat01-#{:counters.get(counter, 1)}",
          "token_type" => "Bearer",
          "expires_in" => expires_in
        })
      )
    end)

    allow_cache()
  end

  # Fly labels the raw JWT application/json; it must be taken as text, not decoded
  test "the identity token is read as text whatever its content type" do
    federate()

    Req.Test.stub(EverydayCitizen.FlyOidc, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln")
    end)

    assert {:ok, {"authorization", "Bearer sk-ant-oat01-0"}} = Credentials.auth_header()

    assert_received {:exchange, _path,
                     %{"assertion" => "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ4In0.c2ln"}}
  end

  test "with federation, the machine's identity token is exchanged for a bearer token" do
    federate()

    assert {:ok, {"authorization", "Bearer sk-ant-oat01-1"}} = Credentials.auth_header()

    assert_received {:oidc, "/v1/tokens/oidc", %{"aud" => "https://api.anthropic.com"}}
    assert_received {:exchange, "/v1/oauth/token", body}

    assert body == %{
             "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
             "assertion" => "jwt-1",
             "federation_rule_id" => "fdrl_test",
             "organization_id" => "org-uuid",
             "service_account_id" => "svac_test",
             "workspace_id" => "wrkspc_test"
           }
  end

  test "the token is reused while it lasts, and renewed with a fresh identity token near expiry" do
    federate()
    {:ok, first} = Credentials.auth_header()
    assert {:ok, ^first} = Credentials.auth_header()
    assert_received {:oidc, _, _}
    refute_received {:oidc, _, _}

    Credentials.reset()
    # a token about to expire (inside the 2-minute margin) is renewed on every use
    federate(100)
    {:ok, {_, "Bearer sk-ant-oat01-1"}} = Credentials.auth_header()
    {:ok, {_, "Bearer sk-ant-oat01-2"}} = Credentials.auth_header()
    assert_received {:exchange, _, %{"assertion" => "jwt-1"}}
    assert_received {:exchange, _, %{"assertion" => "jwt-2"}}
  end

  test "a failed exchange is an error, not a crash" do
    Application.put_env(:everyday_citizen, :anthropic_federation, @federation)
    Req.Test.stub(EverydayCitizen.FlyOidc, &Plug.Conn.send_resp(&1, 200, "jwt"))

    Req.Test.stub(
      EverydayCitizen.Claude,
      &Plug.Conn.send_resp(&1, 401, ~s({"error":"invalid_grant"}))
    )

    allow_cache()

    assert {:error, {:http_status, 401}} = Credentials.auth_header()
  end

  test "without federation the API key is used; with neither, summaries are off and nothing is called" do
    Application.put_env(:everyday_citizen, :anthropic_api_key, "dev-key")
    assert {:ok, {"x-api-key", "dev-key"}} = Credentials.auth_header()
    assert Claude.enabled?()

    Application.put_env(:everyday_citizen, :anthropic_api_key, nil)
    Req.Test.stub(EverydayCitizen.Claude, fn _conn -> flunk("no request without credentials") end)
    assert {:error, :disabled} = Credentials.auth_header()
    refute Claude.enabled?()
    assert {:error, :disabled} = Claude.summarize("text")
  end
end
