defmodule EverydayCitizen.NoNetworkTest do
  @moduledoc "Tests never call outside services: every HTTP request goes through a stubbed plug."
  use ExUnit.Case, async: true

  # the settings each request merges in; in test each holds a Req.Test plug
  @stubbed [:federal_req_options, :anthropic_req_options, :fly_oidc_req_options]

  test "every stubbable request setting has a test plug" do
    for key <- @stubbed do
      assert {Req.Test, _name} = Application.get_env(:everyday_citizen, key)[:plug],
             "#{key} has no plug"
    end
  end

  test "app code makes HTTP requests only with a stubbable setting" do
    offenders =
      for file <- Path.wildcard("lib/**/*.ex"),
          source = File.read!(file),
          source =~ ~r/Req\.(get|post|put|patch|delete|request|new|run)\b/,
          not Enum.any?(@stubbed, &String.contains?(source, ":#{&1}")),
          do: file

    assert offenders == [], "HTTP calls without a test plug: #{inspect(offenders)}"
  end

  test "mail is never sent for real" do
    assert Application.get_env(:everyday_citizen, EverydayCitizen.Mailer)[:adapter] ==
             Swoosh.Adapters.Test
  end
end
