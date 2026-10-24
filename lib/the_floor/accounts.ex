defmodule TheFloor.Accounts do
  @moduledoc """
  Accounts: sign-in by emailed link (and, see `Accounts.Passkeys`, passkeys);
  there are no passwords. An account holds an email, a district key and daily
  email settings.
  """

  import Ecto.Query, warn: false
  alias TheFloor.Repo

  alias TheFloor.Accounts.{User, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `TheFloor.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Mints a single-use, 60-second token that carries a verified passkey sign-in
  from the login LiveView to the session controller.
  """
  def generate_passkey_login_token(%User{} = user, key) do
    {encoded, user_token} = UserToken.build_passkey_login_token(user, key)
    Repo.insert!(user_token)
    encoded
  end

  @doc """
  Consumes a passkey sign-in token. The user carries `session_key_id`, so the
  session created from it is tied to that passkey.
  """
  def login_user_by_passkey_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_passkey_login_token_query(token),
         {%User{} = user, user_token} <- Repo.one(query),
         {1, _} <- Repo.delete_all(from t in UserToken, where: t.id == ^user_token.id) do
      {:ok, user}
    else
      _ -> {:error, :invalid}
    end
  end

  def login_user_by_passkey_token(_token), do: {:error, :invalid}

  @doc """
  Whether another emailed sign-in link may go to this account now: at most one
  a minute and five an hour, so the site cannot be used to flood a mailbox.
  """
  @spec login_link_allowed?(User.t()) :: boolean()
  def login_link_allowed?(%User{id: id}) do
    recent = fn seconds ->
      Repo.aggregate(
        from(t in UserToken,
          where:
            t.user_id == ^id and t.context == "login" and t.inserted_at > ago(^seconds, "second")
        ),
        :count
      )
    end

    recent.(60) == 0 and recent.(3600) < 5
  end

  @doc "Gets a user by id, or nil."
  def get_user(id), do: Repo.get(User, id)

  @doc "Turns the daily email on (starting from now) or off."
  @spec set_digest(User.t(), boolean()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def set_digest(%User{} = user, enabled?) when is_boolean(enabled?) do
    # turned back on, the email starts from now, not from when it was turned off
    sent_at = if enabled?, do: DateTime.utc_now(:second), else: user.digest_sent_at

    user
    |> User.digest_changeset(enabled?)
    |> Ecto.Changeset.put_change(:digest_sent_at, sent_at)
    |> Repo.update()
  end

  @doc "Records the cutoff the last daily email covered."
  def put_digest_sent_at(%User{} = user, %DateTime{} = cutoff),
    do: user |> Ecto.Changeset.change(digest_sent_at: cutoff) |> Repo.update()

  @doc "Ids of people with the daily email on who follow something."
  @spec digest_recipient_ids() :: [integer()]
  def digest_recipient_ids do
    Repo.all(
      from u in User,
        where: u.digest_enabled and not is_nil(u.confirmed_at),
        where: u.id in subquery(from f in TheFloor.Follows.Follow, select: f.user_id),
        select: u.id
    )
  end

  @doc "Saves a district key (never an address) on the account."
  @spec put_district(User.t(), String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def put_district(%User{} = user, district) when is_binary(district) do
    user |> User.district_changeset(district) |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are two cases (accounts have no passwords):

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email. The user gets confirmed,
     logged in, and all tokens - including session ones - are expired.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
