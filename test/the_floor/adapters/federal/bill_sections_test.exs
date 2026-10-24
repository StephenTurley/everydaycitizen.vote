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

  test "law quoted into a section keeps its own numbers, headings and levels" do
    xml = """
    <bill><legis-body><section><enum>1.</enum><header>Amendment</header>
    <text>Section 5 is amended by adding:</text>
    <quoted-block><section><enum>6.</enum><header>New</header>
    <subsection><enum>(a)</enum><header>Rule</header><text>Inserted text.</text>
    <paragraph><enum>(1)</enum><text>First.</text></paragraph></subsection>
    </section><after-quoted-block>.</after-quoted-block></quoted-block>
    </section></legis-body></bill>
    """

    assert {:ok, [%{"kind" => "section", "blocks" => blocks}]} = BillSections.parse(xml)

    assert [
             %{"level" => 0, "text" => "Section 5 is amended by adding:"},
             %{
               "level" => 0,
               "quote" => [
                 %{"level" => 0, "enum" => "6.", "heading" => "New", "text" => ""},
                 %{
                   "level" => 0,
                   "enum" => "(a)",
                   "heading" => "Rule",
                   "text" => "Inserted text."
                 },
                 %{"level" => 1, "enum" => "(1)", "text" => "First."}
               ]
             }
           ] = blocks

    refute Enum.any?(blocks, &((&1["text"] || "") =~ "Inserted text."))
  end

  test "a quote inside a paragraph sits at the paragraph's level, before its later siblings" do
    xml = """
    <bill><legis-body><section><enum>2.</enum><header>Changes</header>
    <subsection><enum>(a)</enum><text>Amendments.</text>
    <paragraph><enum>(1)</enum><text>by inserting:</text>
    <quoted-block><paragraph><enum>(4)</enum><text>New paragraph.</text></paragraph></quoted-block></paragraph>
    <paragraph><enum>(2)</enum><text>by striking.</text></paragraph></subsection>
    </section></legis-body></bill>
    """

    assert {:ok, [%{"blocks" => blocks}]} = BillSections.parse(xml)

    assert [
             %{"enum" => "(a)"},
             %{"enum" => "(1)", "level" => 1},
             %{
               "level" => 1,
               "quote" => [%{"enum" => "(4)", "level" => 1, "text" => "New paragraph."}]
             },
             %{"enum" => "(2)", "level" => 1}
           ] = blocks
  end

  test "USLM quoted content is kept the same way" do
    xml = """
    <bill xmlns="http://schemas.gpo.gov/xml/uslm"><main><section><num>1.</num><heading>Amendment</heading>
    <content>Section 5 is amended by adding:</content>
    <quotedContent><section><num>6.</num><heading>New</heading><content>Inserted text.</content></section></quotedContent>
    </section></main></bill>
    """

    assert {:ok, [%{"blocks" => [_, %{"quote" => [%{"enum" => "6.", "heading" => "New"}]}]}]} =
             BillSections.parse(xml)
  end

  test "words after a quote are kept; a lone closing period is dropped" do
    xml = """
    <bill><legis-body><section><enum>3.</enum><header>More</header><text>Amended by adding:</text>
    <quoted-block><paragraph><enum>(5)</enum><text>Five.</text></paragraph><after-quoted-block>; and</after-quoted-block></quoted-block>
    </section></legis-body></bill>
    """

    assert {:ok, [%{"blocks" => [_, %{"quote" => _}, %{"level" => 0, "text" => "; and"}]}]} =
             BillSections.parse(xml)
  end

  test "NUL characters (which the database cannot store) are dropped from text" do
    xml =
      "<bill><section><enum>1.</enum><header>A&#0;</header><text>a&#0;b</text></section></bill>"

    assert {:ok, [%{"heading" => "A", "blocks" => [%{"text" => "ab"}]}]} = BillSections.parse(xml)
  end

  test "the format number marks the splitter's output shape" do
    assert BillSections.format() == 2
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
