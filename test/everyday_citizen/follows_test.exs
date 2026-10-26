defmodule EverydayCitizen.FollowsTest do
  use EverydayCitizen.DataCase, async: true

  import EverydayCitizen.AccountsFixtures

  alias EverydayCitizen.Follows
  alias EverydayCitizen.Follows.Follow
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records

  setup do
    people = EverydayCitizen.FloorFixtures.iowa!()
    bill = EverydayCitizen.Legislation.get_bill("federal", "119-s-5")
    Map.merge(people, %{bill: bill, scope: user_scope_fixture()})
  end

  test "following is idempotent and visible only to its owner", %{scope: scope, bill: bill} do
    assert {:ok, %Follow{}} = Follows.follow(scope, {:bill, bill.id})
    assert {:ok, %Follow{}} = Follows.follow(scope, {:bill, bill.id})
    assert Repo.aggregate(Follow, :count) == 1

    assert Follows.following?(scope, {:bill, bill.id})
    refute Follows.following?(user_scope_fixture(), {:bill, bill.id})
    assert Follows.followed_bill_ids(scope) == [bill.id]
    assert Follows.followed_bill_ids(user_scope_fixture()) == []
  end

  test "a rep can be followed and unfollowed", %{scope: scope, grassley: g} do
    {:ok, _} = Follows.follow(scope, {:person, g.id})
    assert Follows.followed_person_ids(scope) == [g.id]

    assert :ok = Follows.unfollow(scope, {:person, g.id})
    refute Follows.following?(scope, {:person, g.id})
    assert :ok = Follows.unfollow(scope, {:person, g.id})
  end

  test "list names each followed bill and rep, newest first", %{
    scope: scope,
    bill: bill,
    grassley: g
  } do
    {:ok, _} = Follows.follow(scope, {:bill, bill.id})
    {:ok, _} = Follows.follow(scope, {:person, g.id})

    assert [
             %{target: {:person, _}, person: %{name: "Chuck Grassley"}},
             %{target: {:bill, _}, bill: %{identifier: "S. 5"}}
           ] =
             Follows.list(scope)
  end

  test "This week's followed filter shows only events on followed bills", %{bill: bill} do
    src = Records.SourceRef.new("https://x.test/e", "e")

    for {id, bills} <- [{"floor-1", ["119-s-5"]}, {"floor-2", []}] do
      {:ok, _} =
        Ingest.write(
          %Records.Event{
            jurisdiction: "federal",
            body_external_id: "senate",
            external_id: id,
            classification: "floor",
            title: id,
            date: ~D[2026-10-26],
            start_at: ~U[2026-10-26 14:00:00Z],
            bill_external_ids: bills,
            source: src
          },
          nil
        )
    end

    assert [%{events: [%{title: "floor-1"}]}] =
             EverydayCitizen.Calendar.week("federal", ~D[2026-10-26], bills: [bill.id])

    assert [%{events: [_, _]}] = EverydayCitizen.Calendar.week("federal", ~D[2026-10-26], [])
  end
end
