require "rails_helper"

# A04: whether a partner is a natural person decides if its name is masked for the language model. Unknown is treated as a person, the prudent reading.
RSpec.describe "A partner that is a natural person or a company (A04)", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { sign_in accountant }

  it "starts as not known" do
    expect(create(:partner).is_natural_person).to be_nil
  end

  it "is chosen on the form: person, company, or not known" do
    get new_accounting_partner_path

    expect(response.body).to include("Natural person", "Company or organization", "Not known (treated as a person)")
  end

  { "true" => true, "false" => false, "" => nil }.each do |value, expected|
    it "records #{value.inspect} as #{expected.inspect}" do
      post accounting_partners_path, params: { accounting_partner: { name: "Chosen #{value}", partner_type: "customer", is_natural_person: value } }

      expect(Accounting::Partner.find_by(name: "Chosen #{value}").is_natural_person).to eq(expected)
    end
  end

  it "can be changed afterwards" do
    partner = create(:partner)

    patch accounting_partner_path(partner), params: { accounting_partner: { is_natural_person: "true" } }

    expect(partner.reload.is_natural_person).to be true
  end
end
