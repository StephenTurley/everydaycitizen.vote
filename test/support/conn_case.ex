defmodule EverydayCitizenWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EverydayCitizenWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint EverydayCitizenWeb.Endpoint

      use EverydayCitizenWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EverydayCitizenWeb.ConnCase
    end
  end

  setup tags do
    EverydayCitizen.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Asserts `html` has at least `count` `<details>` elements and that each has an
  id and keeps its `open` attribute through LiveView patches
  (`JS.ignore_attributes(["open"])` on mount). Returns the ids.
  """
  def assert_details_keep_open(html, count \\ 1) do
    details = html |> LazyHTML.from_document() |> LazyHTML.query("details")
    ids = LazyHTML.attribute(details, "id")
    mounted = LazyHTML.attribute(details, "phx-mounted")

    ExUnit.Assertions.assert(length(ids) >= count, "expected #{count}+ details with ids")

    ExUnit.Assertions.assert(
      length(ids) == length(Enum.to_list(details)),
      "a details lacks an id"
    )

    ExUnit.Assertions.assert(length(Enum.uniq(ids)) == length(ids), "details ids repeat")
    ExUnit.Assertions.assert(length(mounted) == length(ids), "a details lacks phx-mounted")

    for js <- mounted do
      ExUnit.Assertions.assert(
        ["ignore_attrs", %{"attrs" => ["open"]}] in Jason.decode!(js),
        "phx-mounted does not ignore open: #{js}"
      )
    end

    ids
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = EverydayCitizen.AccountsFixtures.user_fixture()
    scope = EverydayCitizen.Accounts.Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = EverydayCitizen.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    EverydayCitizen.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
