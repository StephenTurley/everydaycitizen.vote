defmodule EverydayCitizenWeb.SavedDistrictChangeoverTest do
  # changes the :federal config's date
  use EverydayCitizenWeb.ConnCase, async: false

  import EverydayCitizen.AccountsFixtures
  import EverydayCitizen.FederalDate

  alias EverydayCitizen.Accounts
  alias EverydayCitizen.Repo

  @notice "District lines have changed since you last looked up your address."

  setup do
    on(~D[2027-01-10])
    :ok
  end

  test "a district saved before maps were recorded is dropped once the map has changed", %{
    conn: conn
  } do
    conn = conn |> init_test_session(%{district: "IA-1"}) |> get(~p"/")

    refute get_session(conn, :district)
    assert html_response(conn, 200) =~ @notice
  end

  test "an account's district saved before maps were recorded is cleared once the map has changed",
       %{conn: conn} do
    {:ok, user} = Accounts.put_district(user_fixture(), "IA-1", nil)
    conn = conn |> log_in_user(user) |> get(~p"/")

    refute get_session(conn, :district)
    assert %{district: nil, district_map: nil} = Repo.reload(user)
  end
end
