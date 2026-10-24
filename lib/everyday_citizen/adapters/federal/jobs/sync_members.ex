defmodule EverydayCitizen.Adapters.Federal.Jobs.SyncMembers do
  @moduledoc """
  Loads legislators and committees from unitedstates/congress-legislators (the
  source of the Senate LIS ids that Senate votes need): people, chamber
  memberships, committee bodies, then committee memberships. Snoozes until the
  congress session is stored (`Federal.Prerequisites`).
  """
  use Oban.Worker, queue: :ingest, max_attempts: 3

  require Logger

  alias EverydayCitizen.Adapters.Federal.{HTTP, Job, Prerequisites}
  alias EverydayCitizen.Adapters.Federal.Normalize.{Committees, Members}
  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records.{Body, Person}
  alias EverydayCitizen.Legislature

  @base "https://unitedstates.github.io/congress-legislators/"

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    number =
      to_string(
        args["congress"] || Application.fetch_env!(:everyday_citizen, :federal)[:congress]
      )

    with :ok <- Prerequisites.check(job, [Prerequisites.session(number)]) do
      sync(number)
    end
  end

  defp sync(number) do
    Job.run("sync_members", fn run_id, _cursor ->
      with {:ok, session_start} <- session_start(number),
           {:ok, current, src_current} <- fetch("legislators-current"),
           {:ok, historical, src_historical} <- fetch("legislators-historical"),
           {:ok, committees, src_committees} <- fetch("committees-current"),
           {:ok, seats, src_seats} <- fetch("committee-membership-current") do
        member_records =
          Members.records(current, session_start, src_current) ++
            Members.records(historical, session_start, src_historical)

        committee_records = Committees.records(committees, seats, src_committees, src_seats)
        {:ok, write_groups(member_records, committee_records, run_id)}
      end
    end)
  end

  defp write_groups(member_records, committee_records, run_id) do
    {people, chamber_seats} = Enum.split_with(member_records, &match?(%Person{}, &1))
    {bodies, committee_seats} = Enum.split_with(committee_records, &match?(%Body{}, &1))

    {written, skipped} =
      [people, chamber_seats, bodies, committee_seats]
      |> Enum.map(&write_all(&1, run_id))
      |> Enum.reduce({0, 0}, fn {w, s}, {aw, as} -> {aw + w, as + s} end)

    %{people: length(people), bodies: length(bodies), written: written, skipped: skipped}
  end

  defp session_start(number) do
    case Legislature.get_session("federal", number) do
      %{start_date: %Date{} = date} -> {:ok, date}
      _ -> {:error, {:missing_session, number}}
    end
  end

  defp fetch(name) do
    with {:ok, %{body: body, source: source}} <- HTTP.get(@base <> name <> ".json") do
      {:ok, body, source}
    end
  end

  defp write_all(records, run_id) do
    Enum.reduce(records, {0, 0}, fn record, {written, skipped} ->
      case Ingest.write(record, run_id) do
        {:ok, _} ->
          {written + 1, skipped}

        {:error, {:unknown_person, ref}} ->
          Logger.warning("skipping membership for unknown person #{inspect(ref)}")
          {written, skipped + 1}

        {:error, reason} ->
          raise "write failed: #{inspect(reason)} for #{inspect(record, limit: 3)}"
      end
    end)
  end
end
