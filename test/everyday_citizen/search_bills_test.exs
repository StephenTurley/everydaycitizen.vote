defmodule EverydayCitizen.SearchBillsTest do
  use EverydayCitizen.DataCase, async: true
  use Oban.Testing, repo: EverydayCitizen.Repo

  alias EverydayCitizen.Ingest
  alias EverydayCitizen.Ingest.Records
  alias EverydayCitizen.Legislation
  alias EverydayCitizen.Search
  alias EverydayCitizen.Search.Query
  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.Inputs

  defp search(q) do
    {:search, query} = Query.classify(q)
    query
  end

  defp write!(record) do
    {:ok, row} = Ingest.write(record, nil)
    row
  end

  setup do
    write!(%Records.Jurisdiction{
      key: "fed",
      name: "Fed",
      classification: "federal",
      source: source_ref()
    })

    write!(%Records.LegislativeSession{
      jurisdiction: "fed",
      identifier: "118",
      source: source_ref()
    })

    write!(%Records.LegislativeSession{
      jurisdiction: "fed",
      identifier: "119",
      source: source_ref()
    })

    write!(%Records.LegislativeSession{
      jurisdiction: "fed",
      identifier: "119-1",
      parent_identifier: "119",
      source: source_ref()
    })

    write!(%Records.Body{
      jurisdiction: "fed",
      external_id: "lower",
      name: "Lower",
      classification: "chamber",
      source: source_ref()
    })

    :ok
  end

  defp bill!(external_id, identifier, title, opts \\ []) do
    write!(%Records.Bill{
      jurisdiction: "fed",
      session_identifier: Keyword.get(opts, :session, "119"),
      external_id: external_id,
      identifier: identifier,
      classification: "bill",
      title: title,
      subjects: [],
      introduced_on: Keyword.get(opts, :introduced_on, ~D[2026-01-03]),
      source: source_ref()
    })

    if titles = opts[:titles] do
      write!(%Records.BillTitles{
        jurisdiction: "fed",
        bill_external_id: external_id,
        titles: Enum.map(titles, &%{title: &1, kind: "popular"}),
        source: source_ref()
      })
    end

    if actions = opts[:actions] do
      write!(%Records.BillActions{
        jurisdiction: "fed",
        bill_external_id: external_id,
        actions:
          actions
          |> Enum.with_index()
          |> Enum.map(fn {classification, i} ->
            %Records.BillAction{
              position: i,
              date: ~D[2026-02-01],
              description: classification,
              classification: classification
            }
          end),
        source: source_ref()
      })
    end

    if opts[:vote] do
      write!(%Records.Vote{
        jurisdiction: "fed",
        body_external_id: "lower",
        session_identifier: "119-1",
        external_id: "vote-#{external_id}",
        identifier: "Roll Call 1",
        question: "On Passage",
        classification: "passage",
        result: "Failed",
        passed: false,
        voted_at: ~U[2026-02-01 17:00:00Z],
        bill_external_id: external_id,
        counts: %{yea: 1, nay: 2, present: 0, absent: 0},
        positions: [],
        source: source_ref()
      })
    end

    Legislation.get_bill("fed", external_id)
  end

  defp version!(bill, code, date, plain_text) do
    write!(%Records.BillVersion{
      jurisdiction: "fed",
      bill_external_id: bill.external_id,
      code: code,
      classification: code,
      date: date,
      source: source_ref()
    })

    write!(%Records.BillVersionText{
      jurisdiction: "fed",
      bill_external_id: bill.external_id,
      code: code,
      xml: "<bill/>",
      xml_schema: "other",
      plain_text: plain_text,
      source: source_ref()
    })
  end

  describe "bill_by_number/1" do
    setup do
      bill!("119-hr-22", "H.R. 22", "SAVE Act")
      bill!("119-s-22", "S. 22", "Another bill")
      bill!("119-hr-23", "H.R. 23", "Unrelated")
      :ok
    end

    test "a bill number finds that bill whatever the spacing" do
      for q <- ["H.R. 22", "hr22", "h.r.22"],
          do: assert({:one, %{external_id: "119-hr-22"}} = Search.bill_by_number(search(q)))
    end

    test "a bare number lists every bill with that number" do
      assert {:many, bills} = Search.bill_by_number(search("22"))
      assert Enum.map(bills, & &1.identifier) |> Enum.sort() == ["H.R. 22", "S. 22"]
    end

    test "the same number in two sessions lists both" do
      bill!("118-hr-22", "H.R. 22", "Old SAVE Act", session: "118")
      assert {:many, bills} = Search.bill_by_number(search("hr 22"))
      assert Enum.map(bills, & &1.external_id) |> Enum.sort() == ["118-hr-22", "119-hr-22"]
    end

    test "a number nobody has finds nothing, and a name is not a number" do
      assert :none = Search.bill_by_number(search("hr 999"))
      assert :none = Search.bill_by_number(search("save act"))
    end
  end

  describe "bills_by_name/2" do
    test "a popular name finds the bill stored under its formal title" do
      bill!("119-hr-1", "H.R. 1", "An act to provide for reconciliation pursuant to title II",
        titles: ["One Big Beautiful Bill Act"]
      )

      assert [%{bill: %{external_id: "119-hr-1"}, title: "One Big Beautiful Bill Act"} | _] =
               Search.bills_by_name(search("big beautiful bill"), 10)
    end

    test "a whole-name match outranks a bill that only mentions the name" do
      bill!("119-hr-22", "H.R. 22", "SAVE Act")

      bill!("119-hr-5904", "H.R. 5904", "To amend the SAVE Act to extend deadlines",
        actions: ["introduced", "passed_chamber"]
      )

      assert [%{bill: %{external_id: "119-hr-22"}}, %{bill: %{external_id: "119-hr-5904"}}] =
               Search.bills_by_name(search("save act"), 10)
    end

    test "within a tier the bill that got further comes first" do
      bill!("119-hr-22", "H.R. 22", "SAVE Act", introduced_on: ~D[2026-03-01])
      bill!("118-hr-8281", "H.R. 8281", "SAVE Act", session: "118", actions: ["passed_chamber"])

      assert [%{stage: :passed}, %{stage: :introduced}] =
               Search.bills_by_name(search("SAVE Act"), 10)
    end

    test "stages rank law, passed, voted, reported, introduced, then newest first" do
      bill!("119-hr-1", "H.R. 1", "Clock Act", introduced_on: ~D[2026-01-01])
      bill!("119-hr-2", "H.R. 2", "Clock Act", introduced_on: ~D[2026-05-01])
      bill!("119-hr-3", "H.R. 3", "Clock Act", actions: ["reported"])
      bill!("119-hr-4", "H.R. 4", "Clock Act", vote: true)
      bill!("119-hr-5", "H.R. 5", "Clock Act", actions: ["passed_chamber"])
      bill!("119-hr-6", "H.R. 6", "Clock Act", actions: ["passed_chamber", "became_law"])

      assert Search.bills_by_name(search("clock"), 10)
             |> Enum.map(&{&1.bill.identifier, &1.stage}) == [
               {"H.R. 6", :law},
               {"H.R. 5", :passed},
               {"H.R. 4", :voted},
               {"H.R. 3", :reported},
               {"H.R. 2", :introduced},
               {"H.R. 1", :introduced}
             ]
    end

    test "a bill appears once, at its best tier, with the title that earned it" do
      bill!("119-hr-9", "H.R. 9", "To amend the Clean Water Act",
        titles: ["Clean Water Act", "Clean Water Protection and Clean Water Act"]
      )

      assert [%{title: "Clean Water Act"}] = Search.bills_by_name(search("clean water act"), 10)
    end

    test "words match in any order, and the limit holds" do
      bill!("119-hr-7", "H.R. 7", "Protecting Kids Online Act")
      bill!("119-hr-8", "H.R. 8", "Online Kids Safety Act")

      assert [_, _] = Search.bills_by_name(search("kids online"), 10)
      assert [_] = Search.bills_by_name(search("kids online"), 1)
    end

    test "an empty key or LIKE wildcards never match every title" do
      bill!("119-hr-7", "H.R. 7", "Protecting Kids Online Act")
      assert [] = Search.bills_by_name(search("act"), 10)
      assert [] = Search.bills_by_name(search("%%"), 10)
      assert [] = Search.bills_by_name(search("__"), 10)
    end

    test "the cached AI summary rides along, and none is started" do
      bill = bill!("119-hr-22", "H.R. 22", "SAVE Act")
      version!(bill, "ih", ~D[2026-01-03], "Section 1. Proof of citizenship.")
      {subject, input} = Inputs.bill(bill)

      {:ok, _} =
        Summaries.put_ai(:bill, subject, input, %{
          summary: "Requires proof of citizenship.",
          model: "m"
        })

      assert [%{summary: text}] = Search.bills_by_name(search("SAVE Act"), 1)
      assert text =~ "citizenship"
      refute_enqueued(worker: EverydayCitizen.Jobs.SummarizeSubject)
    end

    test "a bill without a cached summary has none" do
      bill!("119-hr-22", "H.R. 22", "SAVE Act")
      assert [%{summary: nil}] = Search.bills_by_name(search("SAVE Act"), 10)
    end
  end

  test "text_searchable? is false for common words alone" do
    refute Search.text_searchable?(search("the of"))
    assert Search.text_searchable?(search("daylight time"))
  end

  test "text_searchable? is false for a query of only excluded words" do
    refute Search.text_searchable?(search("-tax"))
    refute Search.text_searchable?(search("a<->b"))
    refute Search.text_searchable?(search("-tax -credit"))
    assert Search.text_searchable?(search("tax -credit"))
  end

  describe "bills_by_text/3" do
    setup do
      a = bill!("119-hr-100", "H.R. 100", "Sunshine Protection Act")
      version!(a, "ih", ~D[2026-01-03], "A bill about clocks.")
      version!(a, "rh", ~D[2026-02-03], "Daylight saving time shall be the permanent time.")

      b = bill!("119-hr-101", "H.R. 101", "Clock Reform Act")
      version!(b, "ih", ~D[2026-01-03], "Daylight saving time ends.")
      version!(b, "rh", ~D[2026-02-03], "Standard time forever.")
      :ok
    end

    test "a phrase finds bills whose latest text contains it, excluding name matches" do
      %{results: [r], total: 1, more?: false} =
        Search.bills_by_text(search("daylight saving time"), [], 1)

      assert r.bill.external_id == "119-hr-100"
      assert r.stage == :introduced
      assert %{parts: [_ | _]} = r.excerpt
      assert %{results: []} = Search.bills_by_text(search("daylight saving time"), [r.bill.id], 1)
    end

    test "results come ten to a page" do
      for n <- 1..12 do
        bill = bill!("119-hr-#{200 + n}", "H.R. #{200 + n}", "Bill #{n}")
        version!(bill, "ih", Date.add(~D[2026-01-01], n), "Lighthouse funding.")
      end

      assert %{results: page1, total: 12, more?: true} =
               Search.bills_by_text(search("lighthouse"), [], 1)

      assert %{results: page2, total: 12, more?: false} =
               Search.bills_by_text(search("lighthouse"), [], 2)

      assert length(page1) == 10 and length(page2) == 2
      assert MapSet.disjoint?(MapSet.new(page1, & &1.bill.id), MapSet.new(page2, & &1.bill.id))
    end

    test "queries with punctuation and operators never raise" do
      for q <- [
            ~s("save act"),
            "a & b",
            "tax: credit",
            "o'brien",
            "!!!",
            "(foo",
            "-x",
            "the of and"
          ],
          do: assert(%{results: _} = Search.bills_by_text(search(q), [], 1))
    end

    test "a quoted phrase finds a bill containing all its words" do
      bill = bill!("119-hr-300", "H.R. 300", "Families Act")
      version!(bill, "ih", ~D[2026-01-03], "Tax rules change. A refundable credit for families.")

      assert %{results: [%{bill: %{external_id: "119-hr-300"}}]} =
               Search.bills_by_text(search(~s("tax credit")), [], 1)
    end

    test "a hyphenated query works" do
      bill = bill!("119-hr-301", "H.R. 301", "Coverage Act")
      version!(bill, "ih", ~D[2026-01-03], "Pre-existing conditions are covered.")

      assert %{results: [%{bill: %{external_id: "119-hr-301"}, excerpt: %{parts: parts}}]} =
               Search.bills_by_text(search("pre-existing conditions"), [], 1)

      assert Enum.any?(parts, &match?({:mark, _}, &1))
    end

    test "the match cap keeps the bills that got furthest" do
      for n <- 1..4 do
        bill = bill!("119-hr-#{400 + n}", "H.R. #{400 + n}", "Bill #{n}")
        version!(bill, "ih", ~D[2026-01-03], "Lighthouse funding.")
      end

      law =
        bill!("119-hr-499", "H.R. 499", "Law",
          actions: ["became_law"],
          introduced_on: ~D[2020-01-01]
        )

      version!(law, "ih", ~D[2026-01-03], "Lighthouse funding.")

      assert %{results: [%{stage: :law, bill: %{external_id: "119-hr-499"}}, _], total: 2} =
               Search.bills_by_text(search("lighthouse"), [], 1, cap: 2)
    end

    test "a query of only excluded words runs no text search" do
      # "-tax" alone would match every bill without the word: a scan of every text
      for q <- ["-tax", "a<->b"],
          do:
            assert(
              %{results: [], total: 0, more?: false} = Search.bills_by_text(search(q), [], 1)
            )
    end

    test "a search that runs past its timeout finds nothing" do
      bill = bill!("119-hr-500", "H.R. 500", "Long Act")
      version!(bill, "ih", ~D[2026-01-03], "Daylight saving time rules.")
      assert %{total: 2} = Search.bills_by_text(search("daylight saving time"), [], 1)

      # thousands more matches, so ranking them takes longer than the 1 ms allowed
      Repo.query!(
        """
        WITH copies AS (
          SELECT n, nextval('bills_id_seq') AS id FROM generate_series(1, 3000) n
        ), new_bills AS (
          INSERT INTO bills
          SELECT (jsonb_populate_record(b, jsonb_build_object(
            'id', c.id, 'external_id', 'copy-' || c.n, 'identifier', 'H.R. ' || (1000 + c.n)))).*
          FROM bills b, copies c WHERE b.id = $1
          RETURNING id
        )
        INSERT INTO bill_versions
        SELECT (jsonb_populate_record(v, jsonb_build_object(
          'id', nextval('bill_versions_id_seq'), 'bill_id', nb.id))).*
        FROM bill_versions v, new_bills nb WHERE v.bill_id = $1
        """,
        [bill.id]
      )

      assert %{results: [], total: 0, more?: false} =
               Search.bills_by_text(search("daylight saving time"), [], 1, timeout_ms: 1)
    end

    test "a query of only stopwords finds nothing" do
      assert %{results: [], total: 0, more?: false} =
               Search.bills_by_text(search("the of"), [], 1)
    end
  end
end
