defmodule EverydayCitizen.Summaries.ConfigTest do
  # not async: it changes the summaries configuration
  use ExUnit.Case, async: false

  alias EverydayCitizen.Summaries

  setup do
    config = Application.fetch_env!(:everyday_citizen, :summaries)
    on_exit(fn -> Application.put_env(:everyday_citizen, :summaries, config) end)
    %{config: config}
  end

  test "the configuration prices every model in use" do
    assert Summaries.check_config!() == :ok
  end

  # a model without rates would fail only after a paid call, with nothing recorded
  test "a model in use without rates stops the app from starting", %{config: config} do
    models = Map.put(config[:models], :rep_week, "claude-unpriced")
    Application.put_env(:everyday_citizen, :summaries, Keyword.put(config, :models, models))

    assert_raise ArgumentError, ~r/claude-unpriced/, fn -> Summaries.check_config!() end
  end
end
