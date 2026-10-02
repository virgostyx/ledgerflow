require "rails_helper"

# "A person confirms each field": what was proposed from a document becomes data only when someone says so.
RSpec.describe Accounting::ConfirmDocumentField do
  include_context "with entity"

  let(:user) { create(:user) }
  let(:document) do
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("Invoice No: INV-9\nTotal incl. VAT 1.210,00")), filename: "a.pdf", user: user)[:document].tap do |doc|
      Accounting::ExtractDocument.call(document: doc)
    end
  end

  def confirm(field, value) = described_class.call(document: document, field: field, value: value, user: user)
  def stored(field) = document.reload.extracted_data.dig("extraction", "fields", field)

  it "confirms a proposed field as it is, and says who and when" do
    result = confirm("invoice_number", "INV-9")

    expect(result).to be_success
    expect(stored("invoice_number")).to include("value" => "INV-9", "confirmed" => true, "confirmed_by" => user.id, "confirmed_at" => be_present)
    expect(stored("invoice_number")["snippet"]).to include("INV-9") # the origin is kept
  end

  it "takes the person's correction instead of the proposal" do
    confirm("total", "1.200,00")

    expect(stored("total")).to include("value" => "1200.00", "confirmed" => true)
  end

  it "accepts a field nothing was proposed for (the person typed it)" do
    confirm("due_date", "2026-04-11")

    expect(stored("due_date")).to include("value" => "2026-04-11", "confirmed" => true, "snippet" => nil)
  end

  it "audits what was proposed, what was confirmed, and by whom" do
    confirm("total", "1.200,00")

    row = Accounting::AuditLog.where(action: "document_field_confirm", auditable_id: document.id).sole
    expect(row.user_id).to eq(user.id)
    expect(row.payload).to include("field" => "total", "from" => "1210.00", "to" => "1200.00")
  end

  describe "values that are refused" do
    {
      "an amount that is not a number" => [ "total", "abc" ],
      "an impossible date"              => [ "invoice_date", "2026-02-31" ],
      "an IBAN with wrong check digits" => [ "iban", "BE68539007547035" ],
      "a Belgian VAT number with wrong check digits" => [ "supplier_vat", "BE0123456748" ],
      "a structured communication with wrong check digits" => [ "structured_communication", "+++123/4567/89000+++" ],
      "a field that does not exist"     => [ "colour", "red" ],
      "a blank value"                   => [ "invoice_number", "  " ]
    }.each do |label, (field, value)|
      it "refuses #{label}" do
        result = confirm(field, value)

        expect(result).to be_failure
        expect(stored(field)&.fetch("confirmed", false)).to be_falsey
      end
    end

    it "refuses a supplier who is not a partner of this entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { create(:partner, :supplier) }

      expect(confirm("supplier_partner_id", foreign.id.to_s)).to be_failure
    end

    it "accepts a supplier of this entity" do
      partner = create(:partner, :supplier)

      expect(confirm("supplier_partner_id", partner.id.to_s)).to be_success
      expect(stored("supplier_partner_id")["value"]).to eq(partner.id)
    end
  end

  it "writes nothing when the document is frozen (linked to a validated entry)" do
    Accounting::LinkDocument.call(document: document, target: create(:journal_entry, :posted), user: user)

    result = confirm("invoice_number", "INV-9")

    expect(result).to be_failure
    expect(stored("invoice_number")["confirmed"]).to be false
    expect(Accounting::AuditLog.where(action: "document_field_confirm")).to be_empty
  end

  it "survives a new extraction: the confirmed value stays" do
    confirm("total", "1.200,00")

    Accounting::ExtractDocument.call(document: document)

    expect(stored("total")).to include("value" => "1200.00", "confirmed" => true)
  end
end
