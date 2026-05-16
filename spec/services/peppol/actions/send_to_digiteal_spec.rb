require "rails_helper"

RSpec.describe Peppol::Actions::SendToDigiteal do
  include_context "with_open_fiscal_year"

  let(:partner)    { create(:partner, :with_vat, name: "Client SA") }
  let(:invoice)    { create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year) }
  let(:sample_xml) { "<Invoice>...</Invoice>" }

  describe ".execute" do
    context "succès Digiteal" do
      before do
        stub_request(:post, %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices})
          .to_return(
            status: 201,
            body: { "id" => "PEPPOL-TEST-001", "status" => "queued" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "ajoute peppol_id au contexte" do
        ctx = LightService::Context.make(invoice: invoice, ubl_xml: sample_xml)
        described_class.execute(ctx)
        expect(ctx[:peppol_id]).to eq("PEPPOL-TEST-001")
      end

      it "ne fail pas le contexte" do
        ctx = LightService::Context.make(invoice: invoice, ubl_xml: sample_xml)
        described_class.execute(ctx)
        expect(ctx).to be_success
      end
    end

    context "erreur Digiteal (422)" do
      before do
        stub_request(:post, %r{#{Regexp.escape(DIGITEAL_API_URL)}/api/invoices})
          .to_return(status: 422, body: { "error" => "Invalid UBL" }.to_json,
                     headers: { "Content-Type" => "application/json" })
      end

      it "fail le contexte" do
        ctx = LightService::Context.make(invoice: invoice, ubl_xml: sample_xml)
        described_class.execute(ctx)
        expect(ctx).to be_failure
      end
    end
  end
end
