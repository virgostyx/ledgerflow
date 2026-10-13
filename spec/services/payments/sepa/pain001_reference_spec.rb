require "rails_helper"

# B01b "builder de fichier avec fichiers de référence": a batch made from known data gives exactly the file kept in spec/fixtures/payments/, byte for byte,
# (WRITE_REFERENCE=1 rewrites it, to be read before it is kept) and the control sum of any batch, whatever the cents, is the exact sum of its payments (no rounding drifts in a file).
RSpec.describe Payments::Sepa::Pain001Builder do
  include_context "with payment batch"

  let(:created_at) { Time.zone.local(2026, 10, 12, 11, 30, 5) }
  let(:reference_file) { Rails.root.join("spec/fixtures/payments/pain001_reference.xml") }

  before { bank.update_columns(iban: "BE71096123456769", bic: "GKCCBEBB") }

  def second_supplier
    create(:partner, :supplier, name: "Beta Corp", iban: nil).tap do |p|
      create(:partner_bank_account, :verified, partner: p, iban: "FR1420041010050500013M02606", holder_name: "Beta Corp", created_by: owner, first_seen_at: 90.days.ago)
    end
  end

  it "gives the reference file, byte for byte" do
    batch = batch_of(posted(unit_price: 1000), posted(partner: second_supplier, unit_price: 250.5, payment_reference: "+++090/9337/55493+++"))
    file = described_class.call(batch, created_at: created_at)

    File.binwrite(reference_file, file) if ENV["WRITE_REFERENCE"]
    expect(file).to eq(File.binread(reference_file))
  end

  describe "the control sum" do
    it "is the exact sum of the payments, to the cent, for amounts with every kind of cents" do
      prices = [ 0.01, 0.07, 10.10, 33.33, 99.99, 100.01, 1234.56, 0.30 ] # incl. VAT these are not round either
      invoices = prices.each_with_index.map { |price, i| posted(partner: (i.even? ? supplier : second_supplier), unit_price: price) }
      batch = batch_of(*invoices)
      doc = Nokogiri::XML(described_class.call(batch, created_at: created_at)).tap(&:remove_namespaces!)

      amounts = doc.xpath("//CdtTrfTxInf/Amt/InstdAmt").map { |node| BigDecimal(node.text) }
      expect(amounts.sum).to eq(batch.total)
      expect(BigDecimal(doc.at("GrpHdr/CtrlSum").text)).to eq(amounts.sum)
      expect(BigDecimal(doc.at("PmtInf/CtrlSum").text)).to eq(amounts.sum)
      expect(doc.at("GrpHdr/NbOfTxs").text.to_i).to eq(amounts.size)
      expect(amounts.map { |a| a.to_s("F").split(".").last.size }).to all(be <= 2)
    end
  end
end
