defmodule EverydayCitizen.BillPage do
  @moduledoc """
  Everything the bill page shows, in one load: the bill with its sponsor and
  cosponsor count, the status steps, the latest action, the viewer's reps' part
  in it, the latest official summary, the text versions (newest first, with
  sections) and the roll calls on it.

  Status steps by kind of measure:

    * bills and joint resolutions: Introduced, Committee, first chamber, second
      chamber, Law;
    * concurrent resolutions: Introduced, Committee, first chamber, second
      chamber, Agreed to;
    * simple resolutions: Introduced, Committee, Agreed to.

  Chamber steps are named after the bodies. Many passage actions carry no
  chamber, so the second chamber counts as passed when a passage action names
  it, when passage actions fall on two different days, or when the measure was
  enrolled, signed or became law.
  """
  import Ecto.Query

  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Legislation.{BillAction, BillVersion, Sponsorship}
  alias EverydayCitizen.Legislature.{Body, Person}
  alias EverydayCitizen.Repo
  alias EverydayCitizen.Votes.{Vote, VotePosition}

  @after_second ~w(enrolled signed became_law)

  @spec load(String.t(), String.t(), [map()]) :: {:ok, map()} | :not_found
  def load(jurisdiction_key, external_id, reps) do
    case Legislation.get_bill(jurisdiction_key, external_id) do
      nil -> :not_found
      bill -> {:ok, page(Repo.preload(bill, [:source, :from_body]), reps)}
    end
  end

  defp page(bill, reps) do
    actions = Repo.all(from a in BillAction, where: a.bill_id == ^bill.id, order_by: a.position)

    sponsorships =
      Repo.all(
        from s in Sponsorship,
          where: s.bill_id == ^bill.id and is_nil(s.withdrawn_on),
          preload: :person
      )

    votes =
      Repo.all(
        from v in Vote,
          where: v.bill_id == ^bill.id,
          order_by: [desc: v.voted_at, desc: v.id],
          preload: :body
      )

    %{
      bill: bill,
      sponsor:
        sponsorships |> Enum.find(&(&1.classification == "primary")) |> then(&(&1 && &1.person)),
      cosponsor_count: Enum.count(sponsorships, &(&1.classification == "cosponsor")),
      cosponsors: cosponsors(sponsorships),
      steps: steps(bill, actions),
      latest_action: List.last(actions),
      reps: Enum.map(reps, &rep_state(&1, sponsorships, votes)),
      summary: Legislation.latest_summary(bill),
      # metadata only: the XML, text and sections of every version would be
      # many MB on large bills; `sections/2` loads one version's
      versions:
        Repo.all(
          from v in BillVersion,
            where: v.bill_id == ^bill.id,
            order_by: [desc_nulls_last: v.date, desc: v.id],
            select: struct(v, [:id, :bill_id, :code, :classification, :date])
        ),
      votes: votes
    }
  end

  # by when they signed on, then by name
  defp cosponsors(sponsorships) do
    sponsorships
    |> Enum.filter(&(&1.classification == "cosponsor"))
    |> Enum.sort_by(&{&1.date || ~D[9999-12-31], &1.person.name})
    |> Enum.map(& &1.person)
  end

  @options ~w(yea nay present absent)

  @doc "Who voted how on a roll call: `{option, people}` groups in yea, nay, present, not voting order, by name."
  @spec vote_positions(integer()) :: [{String.t(), [Person.t()]}]
  def vote_positions(vote_id) do
    by_option =
      from(p in VotePosition,
        join: person in assoc(p, :person),
        where: p.vote_id == ^vote_id,
        order_by: [person.name, person.id],
        select: {p.option, person}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    for option <- @options, people = by_option[option], do: {option, people}
  end

  @doc "The sections of one of the bill's versions (`[]` when not split yet)."
  @spec sections(struct(), String.t() | nil) :: [map()]
  def sections(_bill, nil), do: []

  def sections(bill, code) do
    Repo.one(
      from v in BillVersion, where: v.bill_id == ^bill.id and v.code == ^code, select: v.sections
    ) || []
  end

  defp steps(bill, actions) do
    first = bill.from_body
    second = first && other_chamber(first)
    dates = fn classes -> for a <- actions, a.classification in classes, a.date, do: a.date end

    introduced = bill.introduced_on || List.first(dates.(["introduced"]))
    passed = actions |> Enum.filter(&(&1.classification == "passed_chamber"))

    first_pass =
      passed |> Enum.map(& &1.date) |> Enum.reject(&is_nil/1) |> Enum.min(Date, fn -> nil end)

    second_pass = second_pass(passed, second, dates.(@after_second))
    committee = first_date(dates.(~w(reported markup)))
    law = first_date(dates.(["became_law"]))

    raw =
      case bill.classification do
        "resolution" ->
          [{"Introduced", introduced}, {"Committee", committee}, {"Agreed to", first_pass}]

        "concurrent_resolution" ->
          [
            {"Introduced", introduced},
            {"Committee", committee},
            {name(first), first_pass},
            {name(second), second_pass},
            {"Agreed to", second_pass}
          ]

        _ ->
          [
            {"Introduced", introduced},
            {"Committee", committee},
            {name(first), first_pass},
            {name(second), second_pass},
            {"Law", law}
          ]
      end

    mark(raw)
  end

  # Done steps up to the last one reached; the first step after is current. A
  # done step with no date of its own was passed over (`skipped`).
  defp mark(raw) do
    reached =
      raw
      |> Enum.with_index()
      |> Enum.filter(fn {{_l, d}, _i} -> d end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.max(fn -> -1 end)

    raw
    |> Enum.with_index()
    |> Enum.map(fn {{label, date}, i} ->
      state =
        cond do
          i <= reached -> :done
          i == reached + 1 -> :current
          true -> :todo
        end

      %{
        label: label,
        date: if(state == :done, do: date),
        state: state,
        skipped: state == :done and is_nil(date)
      }
    end)
  end

  defp second_pass(passed, second, later) do
    by_other = for a <- passed, second && a.actor_body_id == second.id, a.date, do: a.date

    distinct_days =
      passed |> Enum.map(& &1.date) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort(Date)

    cond do
      by_other != [] -> Enum.min(by_other, Date)
      length(distinct_days) >= 2 -> Enum.at(distinct_days, 1)
      later != [] -> Enum.min(later, Date)
      true -> nil
    end
  end

  defp other_chamber(%Body{} = body) do
    Repo.one(
      from b in Body,
        where:
          b.jurisdiction_id == ^body.jurisdiction_id and b.classification == "chamber" and
            b.id != ^body.id,
        limit: 1
    )
  end

  defp name(nil), do: "Chamber"
  defp name(%Body{name: name}), do: name

  defp first_date([]), do: nil
  defp first_date(dates), do: Enum.min(dates, Date)

  # Sponsor, then their vote in their own chamber's main roll call, then cosponsor.
  defp rep_state(rep, sponsorships, votes) do
    mine = Enum.find(sponsorships, &(&1.person_id == rep.person.id))

    state =
      cond do
        mine && mine.classification == "primary" -> :sponsor
        option = vote_option(rep, votes) -> option
        mine -> :cosponsor
        main_vote(votes, rep.body.id) -> :not_in_office
        true -> :no_vote
      end

    %{person: rep.person, body: rep.body, state: state, vote: main_vote(votes, rep.body.id)}
  end

  defp vote_option(rep, votes) do
    with %Vote{} = vote <- main_vote(votes, rep.body.id) do
      Repo.one(
        from p in VotePosition,
          where: p.vote_id == ^vote.id and p.person_id == ^rep.person.id,
          select: p.option
      )
    end
  end

  # Passage in that chamber if there was one, else its latest roll call on the bill.
  defp main_vote(votes, body_id) do
    in_body = Enum.filter(votes, &(&1.body_id == body_id))
    Enum.find(in_body, &(&1.classification == "passage")) || List.first(in_body)
  end
end
