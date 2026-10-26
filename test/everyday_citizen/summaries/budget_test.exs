defmodule EverydayCitizen.Summaries.BudgetTest do
  use EverydayCitizen.DataCase, async: true

  alias EverydayCitizen.Summaries
  alias EverydayCitizen.Summaries.AiSummary

  test "each call's cost is recorded at the model's rates, the long-prompt rate above 100K input tokens" do
    # 100,000 × $0.10/M + 1,000,000 × $0.50/M = $0.51 (input at the tier, so base rates)
    :ok = Summaries.record_usage(:section, %{input_tokens: 100_000, output_tokens: 1_000_000})
    assert_in_delta Summaries.spent_today_usd(), 0.51, 0.0001

    :ok = Summaries.record_usage(:section, %{input_tokens: 200_000, output_tokens: 1_000})
    # 200,000 × $0.50/M + 1,000 × $2.50/M = $0.1025
    assert_in_delta Summaries.spent_today_usd(), 0.6125, 0.0001
  end

  test "a bill summary is written by its own model and costs that model's rates" do
    assert Summaries.model(:bill) == "claude-sonnet-5-5"
    assert Summaries.model(:section) == "claude-haiku-5-5"
    # 100,000 × $2/M + 10,000 × $10/M = $0.30
    :ok = Summaries.record_usage(:bill, %{input_tokens: 100_000, output_tokens: 10_000})
    assert_in_delta Summaries.spent_today_usd(), 0.30, 0.0001
  end

  test "new summaries pause once today's spend reaches the daily budget" do
    refute Summaries.over_budget?()
    # $4.00 at $0.10/M input = 40M input tokens, spread under the long-prompt tier
    for _ <- 1..399,
        do: :ok = Summaries.record_usage(:section, %{input_tokens: 100_000, output_tokens: 0})

    refute Summaries.over_budget?()
    :ok = Summaries.record_usage(:section, %{input_tokens: 100_000, output_tokens: 0})
    assert Summaries.over_budget?()
  end

  test "missing token counts cost nothing rather than crash" do
    :ok = Summaries.record_usage(:section, %{input_tokens: nil, output_tokens: nil})
    assert Summaries.spent_today_usd() == 0.0
  end

  test "a bill or week summary is stored once per subject and prompt version, found while its input matches" do
    {:ok, _} = Summaries.put_ai(:bill, "bill:1:is", "input one", %{summary: "S1", model: "m"})
    {:ok, _} = Summaries.put_ai(:bill, "bill:1:is", "input one", %{summary: "S2", model: "m"})

    assert Repo.aggregate(AiSummary, :count) == 1
    assert %AiSummary{summary: "S2"} = Summaries.get_ai(:bill, "bill:1:is", "input one")
    assert Summaries.get_ai(:bill, "bill:1:is", "input two") == nil
    assert Summaries.get_ai(:rep_week, "bill:1:is", "input one") == nil
  end
end
