require "rails_helper"

# Static files crawlers read. The host is the public one given for production.
RSpec.describe "Crawler files in public/" do
  let(:host) { "https://app.ledgerflowmanagment.com" }

  it "robots.txt keeps crawlers off the sign-in pages and points to the sitemap" do
    robots = Rails.public_path.join("robots.txt").read
    expect(robots).to match(/^User-agent: \*$/)
    expect(robots).to match(%r{^Disallow: /users/$})
    expect(robots).to include("Sitemap: #{host}/sitemap.xml")
  end

  it "sitemap.xml is well-formed and lists the landing page" do
    doc = Nokogiri::XML(Rails.public_path.join("sitemap.xml").read) { |c| c.strict }
    urls = doc.remove_namespaces!.xpath("//url/loc").map(&:text)
    expect(urls).to eq([ "#{host}/" ])
  end
end
