defmodule TheFloor.Adapters.Federal.XmlTextTest do
  use ExUnit.Case, async: true

  alias TheFloor.Adapters.Federal.XmlText

  @dir "test/support/fixtures/federal/govinfo"

  test "plain_text puts headings and body on separate collapsed lines" do
    assert {:ok, text} = XmlText.plain_text(File.read!("#{@dir}/BILLS-119hr22ih.xml"))
    lines = String.split(text, "\n")

    assert "Short title" in lines

    assert Enum.any?(lines, &(&1 =~ "This Act may be cited as the"))
    assert Enum.all?(lines, &(&1 == String.trim(&1) and &1 != "" and not (&1 =~ "  ")))

    assert Enum.find_index(lines, &(&1 == "Short title")) <
             Enum.find_index(lines, &(&1 =~ "may be cited"))
  end

  test "plain_text rejects malformed xml" do
    assert {:error, _} = XmlText.plain_text(File.read!("#{@dir}/malformed.xml"))
  end

  test "schema detects USLM namespaces" do
    assert XmlText.schema(File.read!("#{@dir}/uslm_sample.xml")) == "uslm"
    assert XmlText.schema(File.read!("#{@dir}/BILLS-119hr22ih.xml")) == "other"
  end
end
