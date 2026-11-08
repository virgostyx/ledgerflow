require "rails_helper"

# Static pages served by the proxy/app when a request cannot be answered normally: they must say whose site it is and offer a way back.
RSpec.describe "Error pages in public/" do
  {
    "404" => "Page not found", "422" => "Request refused", "500" => "Something went wrong",
    "406-unsupported-browser" => "Browser not supported"
  }.each do |code, heading|
    describe "#{code}.html" do
      let(:html) { Nokogiri::HTML(Rails.public_path.join("#{code}.html").read) }

      it "is branded, says what happened and links back to the home page" do
        expect(html.at_css("title").text).to include("LedgerFlow", code[0, 3])
        expect(html.at_css("h1").text).to eq(heading)
        expect(html.at_css("a[href='/']")).to be_present
      end

      it "stays out of search indexes and works on a phone" do
        expect(html.at_css("meta[name=robots]")["content"]).to include("noindex")
        expect(html.at_css("meta[name=viewport]")["content"]).to include("width=device-width")
      end

      it "loads nothing from elsewhere (it must render when the app is down)" do
        expect(html.css("script, link[rel=stylesheet], img[src^=http]")).to be_empty
      end
    end
  end
end
