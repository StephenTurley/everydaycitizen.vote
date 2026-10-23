defmodule TheFloor.Ingest.RateLimiterTest do
  use ExUnit.Case, async: true

  alias TheFloor.Ingest.RateLimiter

  test "acquire/1 spaces grants" do
    start_supervised!({RateLimiter, name: :rl_test, interval_ms: 50})
    start = System.monotonic_time(:millisecond)
    for _ <- 1..3, do: assert(:ok = RateLimiter.acquire(:rl_test))
    assert System.monotonic_time(:millisecond) - start >= 100
  end
end
