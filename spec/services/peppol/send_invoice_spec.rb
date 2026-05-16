require "rails_helper"

RSpec.describe Peppol::SendInvoice do
  include_context "with_open_fiscal_year"

  let(:partner) { create(:partner, :with_vat, name: "Client SA") }
  let(:invoice) do
    inv = create(:invoice, :posted,
                 partner: partner, fiscal_year: fiscal_year,
                 invoice_number: "VTE2025/0001",
                 invoice_date: Date.new(2025, 1, 15))
    account = create(:account, code: "700000")
    create(:invoice_line, invoice: inv, account: account,
           description: "Service conseil", quantity: 1,
           unit_price: "1000.00", vat_rate: "21.00", position: 1)
    inv.compute_totals; inv.save!
    inv
  end

  context "succès" do
    before do
      stub_request(:post, %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices})
        .to_return(
          status: 201,
          body: { "id" => "PEPPOL-2025-001", "status" => "queued" }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "retourne un contexte de succès" do
      result = described_class.call(invoice: invoice)
      expect(result).to be_success
    end

    it "met à jour peppol_id sur la facture" do
      described_class.call(invoice: invoice)
      expect(invoice.reload.peppol_id).to eq("PEPPOL-2025-001")
    end

    it "met à jour peppol_status à queued" do
      described_class.call(invoice: invoice)
      expect(invoice.reload.peppol_status).to eq("queued")
    end
  end

  context "erreur Digiteal" do
    before do
      stub_request(:post, %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices})
        .to_return(status: 422, body: { "error" => "Invalid UBL" }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "retourne un contexte d'échec" do
      result = described_class.call(invoice: invoice)
      expect(result).to be_failure
    end

    it "ne met pas à jour peppol_id" do
      described_class.call(invoice: invoice)
      expect(invoice.reload.peppol_id).to be_nil
    end
  end

  context "erreur inattendue lors de la transaction" do
    before do
      allow(ApplicationRecord).to receive(:transaction).and_raise(RuntimeError, "unexpected error")
    end

    it "retourne un contexte d'échec" do
      result = described_class.call(invoice: invoice)
      expect(result).to be_failure
    end
  end

  context "facture non validée (draft)" do
    let(:draft_invoice) { create(:invoice, :draft, partner: partner, fiscal_year: fiscal_year) }

    it "retourne un contexte d'échec" do
      result = described_class.call(invoice: draft_invoice)
      expect(result).to be_failure
    end
  end
end
