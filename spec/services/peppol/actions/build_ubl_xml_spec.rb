require "rails_helper"

RSpec.describe Peppol::Actions::BuildUblXml do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat, name: "Client SA") }
  let(:invoice) do
    inv = create(:invoice, :posted,
                 partner: partner, fiscal_year: fiscal_year,
                 invoice_number: "VTE2025/0001",
                 invoice_date: Date.new(2025, 1, 15))
    account = create(:account, code: "700000")
    create(:invoice_line, invoice: inv, account: account,
           description: "Service", quantity: 1, unit_price: "100.00", vat_rate: "21.00", position: 1)
    inv.compute_totals; inv.save!
    inv
  end

  describe ".execute" do
    it "ajoute ubl_xml au contexte" do
      ctx = LightService::Context.make(invoice: invoice)
      described_class.execute(ctx)
      expect(ctx[:ubl_xml]).to be_present
      expect(ctx[:ubl_xml]).to include("VTE2025/0001")
    end

    it "ne fail pas le contexte" do
      ctx = LightService::Context.make(invoice: invoice)
      described_class.execute(ctx)
      expect(ctx).to be_success
    end
  end
end
