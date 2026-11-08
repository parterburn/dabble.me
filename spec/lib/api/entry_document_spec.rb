# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::EntryDocument do
  def run(text, **format)
    { "text" => text }.merge(format.transform_keys(&:to_s))
  end

  def paragraph(*runs)
    { "type" => "paragraph", "runs" => runs }
  end

  describe ".from_html" do
    it "reads paragraphs and line breaks from web/simple_format HTML" do
      html = "<p>Line one\n<br />line two</p>\n\n<p>Second</p>"
      expect(described_class.from_html(html)).to eq([
        paragraph(run("Line one\nline two")),
        paragraph(run("Second"))
      ])
    end

    it "reads the formatting the web editor produces" do
      html = %(<p>I <b>loved</b> <i>it</i>, <u>really</u>. <a href="https://x.test" target="_blank">Link</a></p>) +
             "<ul><li>one</li><li><strong>two</strong></li></ul><ol><li>first</li></ol>"
      expect(described_class.from_html(html)).to eq([
        paragraph(run("I "), run("loved", bold: true), run(" "), run("it", italic: true), run(", "),
                  run("really", underline: true), run(". "), run("Link", link: "https://x.test")),
        { "type" => "bullet", "runs" => [run("one")] },
        { "type" => "bullet", "runs" => [run("two", bold: true)] },
        { "type" => "number", "runs" => [run("first")] }
      ])
    end

    it "treats email <div> lines as line breaks and empty divs as paragraph breaks" do
      html = "<div>Morning run</div><div>then coffee</div><div><br></div><div>Long day.</div>"
      expect(described_class.from_html(html)).to eq([
        paragraph(run("Morning run\nthen coffee")),
        paragraph(run("Long day."))
      ])
    end

    it "keeps merged replies separated by a rule" do
      expect(described_class.from_html("<p>One</p><hr><p>Two</p>")).to eq([
        paragraph(run("One")), { "type" => "rule" }, paragraph(run("Two"))
      ])
    end

    it "reads plain email bodies with <br><br> breaks" do
      expect(described_class.from_html("Hi there<br><br>Second &amp; last")).to eq([
        paragraph(run("Hi there\n\nSecond & last"))
      ])
    end

    [
      %(<p><span style="color: red">red</span></p>),
      "<blockquote>quoted</blockquote>",
      %(<div data-content="dabblemegpt">AI reply</div>),
      %(<p><img src="https://x.test/a.png"></p>),
      %(<p>My day</p><div><img src="https://x.test/a.png"></div>),
      %(<div>Text</div><div><span><img src="https://x.test/a.png"></span></div>),
      "<ul><li>outer<ul><li>nested</li></ul></li></ul>",
      %(<p><a href="javascript:alert(1)">x</a></p>),
      "<h1>Heading</h1>"
    ].each do |html|
      it "is nil for #{html}" do
        expect(described_class.from_html(html)).to be_nil
      end
    end
  end

  describe ".to_html" do
    it "renders blocks with escaping and grouped lists" do
      html = described_class.to_html([
        paragraph(run("A <tag> & "), run("bold", bold: true, italic: true), run("\nnext line")),
        { "type" => "bullet", "runs" => [run("x")] },
        { "type" => "bullet", "runs" => [run("y", link: "https://x.test/?a=1&b=2")] },
        { "type" => "rule" },
        { "type" => "number", "runs" => [run("z", underline: true)] }
      ])
      expect(html).to eq(
        "<p>A &lt;tag&gt; &amp; <strong><em>bold</em></strong><br>next line</p>\n" \
        "<ul>\n<li>x</li>\n" +
        %(<li><a href="https://x.test/?a=1&amp;b=2" target="_blank">y</a></li>\n</ul>\n) +
        "<hr>\n<ol>\n<li><u>z</u></li>\n</ol>"
      )
    end

    it "drops unsafe links but keeps the text" do
      html = described_class.to_html([paragraph(run("click", link: "javascript:alert(1)"))])
      expect(html).to eq("<p>click</p>")
    end

    it "ignores unknown run keys" do
      html = described_class.to_html([paragraph({ "text" => "hi", "style" => "color:red", "bold" => "yes" })])
      expect(html).to eq("<p>hi</p>")
    end

    it "rejects malformed documents" do
      expect { described_class.to_html("nope") }.to raise_error(described_class::InvalidDocument)
      expect { described_class.to_html([{ "type" => "script" }]) }.to raise_error(described_class::InvalidDocument)
      expect { described_class.to_html([paragraph({ "text" => 1 })]) }.to raise_error(described_class::InvalidDocument)
    end

    it "round-trips through from_html" do
      blocks = [
        paragraph(run("Hello "), run("world", bold: true), run("\nagain")),
        { "type" => "rule" },
        { "type" => "number", "runs" => [run("one")] },
        { "type" => "number", "runs" => [run("two", link: "https://x.test")] }
      ]
      expect(described_class.from_html(described_class.to_html(blocks))).to eq(blocks)
    end
  end
end
