defmodule EverydayCitizen.Follows do
  @moduledoc """
  What a signed-in person follows: bills and reps. Every function takes the
  caller's scope; one person never sees another's follows. The daily email
  (`EverydayCitizen.Digest`) reads these.
  """
  import Ecto.Query

  alias EverydayCitizen.Accounts.Scope
  alias EverydayCitizen.Follows.Follow
  alias EverydayCitizen.Repo

  @type target :: {:bill, integer()} | {:person, integer()}

  @doc "Follows a bill or a rep; following twice is one follow."
  @spec follow(Scope.t(), target()) :: {:ok, Follow.t()}
  def follow(%Scope{user: user}, target) do
    attrs = Map.put(target_attrs(target), :user_id, user.id)

    Repo.insert!(struct(Follow, attrs),
      on_conflict: :nothing,
      conflict_target: conflict_target(target)
    )

    {:ok, Repo.get_by!(Follow, attrs)}
  end

  @doc "Stops following; not following is fine."
  @spec unfollow(Scope.t(), target()) :: :ok
  def unfollow(%Scope{user: user}, target) do
    Follow
    |> where(^Map.to_list(Map.put(target_attrs(target), :user_id, user.id)))
    |> Repo.delete_all()

    :ok
  end

  @spec following?(Scope.t() | nil, target()) :: boolean()
  def following?(nil, _target), do: false
  def following?(%Scope{user: nil}, _target), do: false

  def following?(%Scope{user: user}, target),
    do:
      Repo.exists?(where(Follow, ^Map.to_list(Map.put(target_attrs(target), :user_id, user.id))))

  @doc "Each follow with its bill or person, newest first."
  @spec list(Scope.t()) :: [%{target: target(), bill: map() | nil, person: map() | nil}]
  def list(%Scope{user: user}) do
    Follow
    |> where(user_id: ^user.id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> preload([:bill, :person])
    |> Repo.all()
    |> Enum.map(fn f ->
      target = if f.bill_id, do: {:bill, f.bill_id}, else: {:person, f.person_id}
      %{target: target, bill: f.bill, person: f.person}
    end)
  end

  @spec followed_bill_ids(Scope.t()) :: [integer()]
  def followed_bill_ids(%Scope{user: user}),
    do:
      Repo.all(
        from f in Follow,
          where: f.user_id == ^user.id and not is_nil(f.bill_id),
          select: f.bill_id
      )

  @spec followed_person_ids(Scope.t()) :: [integer()]
  def followed_person_ids(%Scope{user: user}),
    do:
      Repo.all(
        from f in Follow,
          where: f.user_id == ^user.id and not is_nil(f.person_id),
          select: f.person_id
      )

  defp target_attrs({:bill, id}) when is_integer(id), do: %{bill_id: id}
  defp target_attrs({:person, id}) when is_integer(id), do: %{person_id: id}

  defp conflict_target({:bill, _}),
    do: {:unsafe_fragment, "(user_id, bill_id) WHERE bill_id IS NOT NULL"}

  defp conflict_target({:person, _}),
    do: {:unsafe_fragment, "(user_id, person_id) WHERE person_id IS NOT NULL"}
end
