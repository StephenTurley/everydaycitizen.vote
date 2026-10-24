defmodule TheFloor.Ingest.SafeHtmlTest do
  use ExUnit.Case, async: true

  alias TheFloor.Ingest.SafeHtml

  test "keeps paragraphs, lists and emphasis; drops everything else but its text" do
    html =
      ~s{<p onclick="x()"><strong>SAVE Act</strong> and <a href="https://x.test">a link</a></p>} <>
        ~s{<script>alert(1)</script><ul><li><em>one</em></li></ul><div>plain</div>}

    assert SafeHtml.sanitize(html) ==
             "<p><strong>SAVE Act</strong> and a link</p><ul><li><em>one</em></li></ul>plain"
  end

  test "text is escaped" do
    assert SafeHtml.sanitize("<p>5 &lt; 6 &amp; \"x\"</p>") ==
             "<p>5 &lt; 6 &amp; &quot;x&quot;</p>"
  end
end
