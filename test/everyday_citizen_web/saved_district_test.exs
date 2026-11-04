defmodule EverydayCitizenWeb.SavedDistrictTest do
  use EverydayCitizenWeb.ConnCase, async: true

  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Accounts
  alias EverydayCitizen.Repo

  @notice "District lines have changed since you last looked up your address. Enter it again to see your representatives."

  # the test config's date puts the current map at "119"
  @current "119"

  test "a district from an older map is dropped with the notice", %{conn: conn} do
    conn = conn |> init_test_session(%{district: "IA-1", district_map: "118"}) |> get(~p"/")

    refute get_session(conn, :district)
    refute get_session(conn, :district_map)
    html = html_response(conn, 200)
    assert html =~ @notice
    assert html =~ ~s(id="zip-form")
    refute html =~ ~s(id="your-reps")
  end

  test "a signed-in person's old district is cleared from the account", %{conn: conn} do
    {:ok, user} = Accounts.put_district(user_fixture(), "IA-1", "118")

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:district, "IA-1")
      |> put_session(:district_map, "118")
      |> get(~p"/")

    refute get_session(conn, :district)
    assert html_response(conn, 200) =~ @notice
    assert %{district: nil, district_map: nil} = Repo.reload(user)
  end

  test "an account looked up again elsewhere replaces an old session district", %{conn: conn} do
    {:ok, user} = Accounts.put_district(user_fixture(), "IA-2", @current)

    conn =
      conn
      |> log_in_user(user)
      |> put_session(:district, "IA-1")
      |> put_session(:district_map, "118")
      |> get(~p"/")

    assert get_session(conn, :district) == "IA-2"
    assert get_session(conn, :district_map) == @current
    refute html_response(conn, 200) =~ @notice
  end

  test "a district saved before maps were recorded is stamped, not dropped", %{conn: conn} do
    conn = conn |> init_test_session(%{district: "IA-1"}) |> get(~p"/")

    assert get_session(conn, :district) == "IA-1"
    assert get_session(conn, :district_map) == @current
    html = html_response(conn, 200)
    assert html =~ ~s(id="your-reps")
    refute html =~ @notice
  end

  test "an account's district saved before maps were recorded is stamped", %{conn: conn} do
    {:ok, user} = Accounts.put_district(user_fixture(), "IA-1", nil)
    conn = conn |> log_in_user(user) |> get(~p"/")

    assert get_session(conn, :district) == "IA-1"
    assert Repo.reload(user).district_map == @current
  end

  test "a current district is left alone", %{conn: conn} do
    conn =
      conn |> init_test_session(%{district: "IA-1", district_map: @current}) |> get(~p"/")

    assert get_session(conn, :district) == "IA-1"
    refute html_response(conn, 200) =~ @notice
  end

  test "following a district link saves the current map", %{conn: conn} do
    user = user_fixture()
    conn = conn |> log_in_user(user) |> get(~p"/district/IA-1")

    assert get_session(conn, :district_map) == @current
    assert %{district: "IA-1", district_map: @current} = Repo.reload(user)
  end
end
