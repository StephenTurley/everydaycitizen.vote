defmodule TheFloor.Adapters.Federal.BillSectionsTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.BillSections

  @dir "test/support/fixtures/federal/govinfo"

  defp sections(file) do
    {:ok, sections} = "#{@dir}/#{file}" |> File.read!() |> BillSections.parse()
    Enum.filter(sections, &(&1["kind"] == "section"))
  end

  test "the bill's sections, in order, with number and heading" do
    assert [
             %{"enum" => "1.", "heading" => "Short title"},
             %{
               "enum" => "2.",
               "heading" =>
                 "Ensuring only citizens are registered to vote in elections for Federal office"
             },
             %{"enum" => "8.", "heading" => "Effective date"}
           ] = sections("BILLS-119hr22ih.xml")
  end

  test "subsections and deeper levels become indented blocks" do
    [_, sec2, _] = sections("BILLS-119hr22ih.xml")
    [first | _] = sec2["blocks"]

    assert %{
             "level" => 0,
             "enum" => "(a)",
             "heading" => "Definition of documentary proof of United States citizenship"
           } =
             first

    assert Enum.any?(sec2["blocks"], &(&1["level"] == 1))
    assert Enum.all?(sec2["blocks"], &is_binary(&1["text"]))
  end

  test "a section's own text is its first block" do
    [sec1 | _] = sections("BILLS-119hr22ih.xml")
    assert [%{"level" => 0, "enum" => nil, "text" => text}] = sec1["blocks"]
    assert text =~ "This Act may be cited as the"
  end

  test "USLM documents parse too" do
    assert [
             %{
               "enum" => "1.",
               "heading" => "Short title",
               "blocks" => [%{"text" => "This Act may be cited as the Sample Act."}]
             }
           ] =
             sections("uslm_sample.xml")
  end

  test "sections quoted into existing law stay inside their block, not as sections" do
    xml = """
    <bill><legis-body><section><enum>1.</enum><header>Amendment</header>
    <text>Section 5 is amended by adding:</text>
    <quoted-block><section><enum>6.</enum><header>New</header><text>Inserted text.</text></section></quoted-block>
    </section></legis-body></bill>
    """

    assert {:ok, [%{"kind" => "section", "enum" => "1.", "blocks" => blocks}]} =
             BillSections.parse(xml)

    assert Enum.map_join(blocks, " ", & &1["text"]) =~ "Inserted text."
  end

  test "titles appear before their sections" do
    xml = """
    <bill><legis-body><title><enum>I</enum><header>Protections</header>
    <section><enum>101.</enum><header>Rights</header><text>Text.</text></section></title></legis-body></bill>
    """

    assert {:ok,
            [
              %{"kind" => "title", "enum" => "I", "heading" => "Protections"},
              %{"kind" => "section", "enum" => "101."}
            ]} =
             BillSections.parse(xml)
  end

  test "metadata titles are not bill titles" do
    {:ok, entries} = "#{@dir}/BILLS-119hr22ih.xml" |> File.read!() |> BillSections.parse()
    assert hd(entries)["kind"] == "section"
  end

  test "malformed XML is an error" do
    assert {:error, _} = "#{@dir}/malformed.xml" |> File.read!() |> BillSections.parse()
  end
end
