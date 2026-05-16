require "rails_helper"

RSpec.describe Peppol::Actions::HandleDeliveryStatus do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat) }
  let(:invoice) do
    create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year)
  end

  describe ".execute" do
    it "met à jour peppol_id et peppol_status sur la facture" do
      ctx = LightService::Context.make(invoice: invoice, peppol_id: "PEPPOL-TEST-001")
      described_class.execute(ctx)
      expect(invoice.reload.peppol_id).to eq("PEPPOL-TEST-001")
      expect(invoice.reload.peppol_status).to eq("queued")
    end

    it "ne fail pas le contexte" do
      ctx = LightService::Context.make(invoice: invoice, peppol_id: "PEPPOL-TEST-001")
      described_class.execute(ctx)
      expect(ctx).to be_success
    end
  end
end
