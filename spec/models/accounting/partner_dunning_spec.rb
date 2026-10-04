require "rails_helper"

RSpec.describe Accounting::Partner, "dunning follow-up" do
  include_context "with entity"

  it "forgets the bounce once the address is changed" do
    partner = create(:partner, email: "old@example.com", email_bounced_at: 1.day.ago)
    partner.update!(name: "Renamed")
    expect(partner.email_bounced_at).to be_present
    partner.update!(email: "new@example.com")
    expect(partner.email_bounced_at).to be_nil
  end
end
