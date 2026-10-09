require "rails_helper"

# B01a §4 "Mobile": an installable web application. The manifest is public (a browser reads it before anyone signs in) and says what is installed.
RSpec.describe "Installable web application", type: :request do
  include_context "with entity"

  it "serves a manifest that a phone can install from" do
    get "/manifest.json"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    manifest = JSON.parse(response.body)
    expect(manifest).to include("name" => "LedgerFlow", "display" => "standalone", "start_url" => "/accounting")
    expect(manifest["icons"].map { |icon| icon["src"] }).to include("/icon.png")
  end

  it "is announced by the pages of the application" do
    sign_in create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) }

    get accounting_root_path

    expect(response.body).to include('<link rel="manifest" href="/manifest.json"')
  end
end
