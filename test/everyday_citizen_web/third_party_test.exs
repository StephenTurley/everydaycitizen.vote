defmodule EverydayCitizenWeb.ThirdPartyTest do
  use EverydayCitizenWeb.ConnCase, async: true

  # A page loads nothing from another host, so no visitor's request reaches a
  # third party (fonts are served from /fonts).
  test "the page loads its scripts, styles and fonts from this site only", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    sources =
      Regex.scan(~r/<(?:link|script|img)\b[^>]*?\b(?:href|src)="([^"]+)"/, html,
        capture: :all_but_first
      )
      |> List.flatten()

    assert "/fonts/public-sans-latin.woff2" in sources
    assert Enum.all?(sources, &String.starts_with?(&1, "/")), inspect(sources)
  end

  test "the fonts are served", %{conn: conn} do
    for name <-
          ~w(public-sans-latin public-sans-latin-ext source-serif-4-latin source-serif-4-latin-ext) do
      assert conn |> get("/fonts/#{name}.woff2") |> response(200) |> byte_size() > 10_000
    end
  end
end
