defmodule EverydayCitizenWeb.AiBoxTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias EverydayCitizenWeb.FloorComponents

  @summary """
  This bill would let partnerships settle.

  ## Who this affects
  - Partnerships: they could settle.
  - Investors: they could owe 25% more.

  ## Words to know
  - Conservation easement: a promise never to develop land.

  ## For example
  Made-up numbers: an investor puts in $100,000.
  - The deduction is capped at 2.5 × $100,000 = $250,000.
  """

  defp box(text) do
    render_component(&FloorComponents.ai_box/1,
      id: "bill-summary",
      title: "In plain English: what this bill does",
      source: "the bill's text below",
      state: {:ok, text},
      prompt_url: "https://example.org/prompt"
    )
  end

  test "the summary's parts render under their own headings" do
    html = box(@summary)
    assert html =~ ~r/<h3[^>]*>\s*Who this affects\s*<\/h3>/
    assert html =~ ~r/<h3[^>]*>\s*Words to know\s*<\/h3>/
    assert html =~ "<li>Investors: they could owe 25% more.</li>"
    refute html =~ "## "
  end

  test "the example is set apart as made up" do
    html = box(@summary)

    example = html |> LazyHTML.from_fragment() |> LazyHTML.query("[data-part=example]")
    assert Enum.count(example) == 1
    assert LazyHTML.text(example) =~ "Made-up numbers: an investor puts in $100,000."
    assert LazyHTML.text(example) =~ "2.5 × $100,000 = $250,000"
  end

  test "a summary without headings renders as before" do
    html = box("One sentence.\n- A point.")
    assert html =~ "<p class=\"m-0\">One sentence.</p>"
    assert html =~ "<li>A point.</li>"
    refute html =~ "<h3"
  end

  test "the published bill prompt asks for the headings the page shows" do
    prompt =
      File.read!(Application.app_dir(:everyday_citizen, "priv/prompts/bill_summary.v3.md"))

    for heading <- ["## Who this affects", "## Words to know", "## For example"],
        do: assert(prompt =~ heading)
  end

  test "clamped, the summary is cut to two lines on phones only" do
    clamped =
      render_component(&FloorComponents.ai_box/1,
        id: "law-summary",
        title: "In plain English",
        source: "the bill",
        state: {:ok, "One.\n\nTwo."},
        prompt_url: "https://example.org/prompt",
        clamp: true
      )

    assert clamped =~ "max-lg:line-clamp-2"
    assert clamped =~ "max-lg:contents"
    refute box("One.") =~ "line-clamp"
  end
end
