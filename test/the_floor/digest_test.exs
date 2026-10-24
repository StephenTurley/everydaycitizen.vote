defmodule TheFloor.DigestTest do
  use TheFloor.DataCase, async: true

  import TheFloor.AccountsFixtures

  alias TheFloor.Accounts.Scope
  alias TheFloor.{Digest, Follows, Repo}
  alias TheFloor.Legislation.{BillAction, BillVersion, Sponsorship}
  alias TheFloor.Votes.Vote

  @old ~U[2026-01-01 00:00:00.000000Z]
  @since ~U[2026-10-01 00:00:00Z]

  setup do
    people = TheFloor.FloorFixtures.iowa!()

    # everything the fixtures stored is old news
    for schema <- [BillAction, BillVersion, Vote, Sponsorship],
        do: Repo.update_all(schema, set: [inserted_at: @old])

    user = user_fixture()
    bill = TheFloor.Legislation.get_bill("federal", "119-s-5")
    Map.merge(people, %{user: user, scope: Scope.for_user(user), bill: bill})
  end

  defp new_action!(bill, classification \\ "reported") do
    Repo.insert!(%BillAction{
      bill_id: bill.id,
      position: 99,
      date: ~D[2026-10-20],
      description: "Reported by the committee.",
      classification: classification,
      source_id: bill.source_id
    })
  end

  defp items(user), do: Digest.items(user, @since, DateTime.utc_now())

  test "nothing first stored since the last digest means no items", %{
    scope: scope,
    bill: bill,
    user: user
  } do
    {:ok, _} = Follows.follow(scope, {:bill, bill.id})
    assert items(user) == []
  end

  test "re-fetching an unchanged bill does not make it new", %{
    scope: scope,
    bill: bill,
    user: user
  } do
    {:ok, _} = Follows.follow(scope, {:bill, bill.id})
    TheFloor.FloorFixtures.iowa!()
    assert items(user) == []
  end

  test "a new action on a followed bill is one item linking to the bill", %{
    scope: scope,
    bill: bill,
    user: user
  } do
    {:ok, _} = Follows.follow(scope, {:bill, bill.id})
    new_action!(bill)

    assert [%{kind: :action, url: "/bills/119-s-5", date: ~D[2026-10-20], detail: detail}] =
             items(user)

    assert detail =~ "Reported by the committee."
  end

  test "a followed rep's vote shows how they voted", %{scope: scope, grassley: g, user: user} do
    {:ok, _} = Follows.follow(scope, {:person, g.id})
    Repo.update_all(Vote, set: [inserted_at: DateTime.utc_now()])

    assert [%{kind: :rep_vote, detail: detail, url: "/bills/119-s-5"} | _] = items(user)
    assert detail =~ "Chuck Grassley voted"
  end

  test "a bill followed directly and through its sponsor appears once", %{
    scope: scope,
    bill: bill,
    ernst: ernst,
    user: user
  } do
    {:ok, _} = Follows.follow(scope, {:bill, bill.id})
    {:ok, _} = Follows.follow(scope, {:person, ernst.id})
    new_action!(bill)

    assert [_one] = items(user)
  end

  test "a bill's action outside the window is not included", %{
    scope: scope,
    bill: bill,
    user: user
  } do
    {:ok, _} = Follows.follow(scope, {:bill, bill.id})
    new_action!(bill)
    assert Digest.items(user, DateTime.utc_now(), DateTime.add(DateTime.utc_now(), 60)) == []
  end

  test "following something new does not email its history from before the follow", %{
    scope: scope,
    grassley: g,
    user: user
  } do
    # the rep's votes were stored after `since` but before the follow
    {:ok, _} = Follows.follow(scope, {:person, g.id})
    assert Digest.items(user, ~U[2025-01-01 00:00:00Z], DateTime.utc_now()) == []
  end

  test "unsubscribe tokens name the user and cannot be forged", %{user: user} do
    token = Digest.unsubscribe_token(user)
    assert {:ok, id} = Digest.verify_unsubscribe(token)
    assert id == user.id
    assert :error = Digest.verify_unsubscribe(token <> "x")
    assert :error = Digest.verify_unsubscribe("nonsense")
  end
end
