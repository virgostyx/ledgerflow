require "rails_helper"

# F06 step 3: a supplier created from a received document is "to validate": it shows in the list, and a person validates it.
RSpec.describe "Partners to validate", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user, role: :accountant) }
  let(:reader)     { create(:user, role: :manager) }
  let!(:membership)        { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:reader_membership) { create(:user_entity, :manager, user: reader, entity: entity) }
  let!(:fresh)  { create(:partner, partner_type: :supplier, name: "Created by Peppol", to_validate: true) }
  let!(:usual)  { create(:partner, partner_type: :supplier, name: "Usual Supplier") }

  before { sign_in accountant }

  it "marks it in the list" do
    get accounting_partners_path

    expect(response.body).to include("Created by Peppol").and include("To validate")
    expect(response.body.scan("To validate").size).to eq(1)
  end

  it "is validated by a person, who is recorded" do
    post validate_accounting_partner_path(fresh)

    expect(fresh.reload.to_validate).to be(false)
    expect(response).to redirect_to(accounting_partners_path)
    expect(Accounting::AuditLog.where(auditable_type: "Accounting::Partner", auditable_id: fresh.id, action: "partner_validated").sole.user_id).to eq(accountant.id)
  end

  it "is refused to a role that cannot write" do
    sign_in reader
    post validate_accounting_partner_path(fresh)

    expect(fresh.reload.to_validate).to be(true)
  end

  it "can be filtered on" do
    get accounting_partners_path, params: { q: { to_validate: "1" } }

    expect(response.body).to include("Created by Peppol").and not_include("Usual Supplier")
  end
end
