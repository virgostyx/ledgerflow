require "rails_helper"

# B01b §5 "Génération du fichier": pain.001 built from a batch, validated against the XSD of its version, the same bytes every time.
RSpec.describe Payments::Sepa::Pain001Builder do
  include_context "with payment batch"

  let(:invoice) { posted }
  let(:batch) { batch_of(invoice) }
  let(:created_at) { Time.zone.local(2026, 10, 12, 11, 30, 5) }

  def build(batch = self.batch, at: created_at) = described_class.call(batch, created_at: at)

  def xml(batch = self.batch) = Nokogiri::XML(build(batch)).tap(&:remove_namespaces!)

  it "gives the same bytes every time for the same batch and the same moment" do
    first = build
    expect(build).to eq(first)
    expect(Digest::SHA256.hexdigest(first)).to eq(Digest::SHA256.hexdigest(build))
  end

  it "changes only the creation time when it is made at another moment" do
    other = build(at: created_at + 1.hour)

    expect(other.sub(/<CreDtTm>[^<]+/, "")).to eq(build.sub(/<CreDtTm>[^<]+/, ""))
    expect(other).not_to eq(build)
  end

  it "is valid against the schema of the version of the profile" do
    xsd = Nokogiri::XML::Schema(File.read(Gem.loaded_specs["sepa_king"].full_gem_path + "/lib/schema/pain.001.001.03.xsd"))

    expect(xsd.validate(Nokogiri::XML(build))).to be_empty
  end

  it "has the header the person compares with the bank: message id, number of payments, control sum, initiator" do
    doc = xml

    expect(doc.at("GrpHdr/MsgId").text).to eq(batch.reference)
    expect(doc.at("GrpHdr/NbOfTxs").text).to eq("1")
    expect(doc.at("GrpHdr/CtrlSum").text).to eq("1210.00")
    expect(doc.at("GrpHdr/InitgPty/Nm").text).to eq("Ledger Flow SRL")
    expect(doc.at("GrpHdr/CreDtTm").text).to eq("2026-10-12T11:30:05")
  end

  it "has one block for the debtor account and the date, and one transaction per payment with its own end-to-end id" do
    two = batch_of(posted(unit_price: 100), posted(partner: create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", created_by: owner, first_seen_at: 90.days.ago) }))
    doc = xml(two)

    expect(doc.xpath("//PmtInf").size).to eq(1)
    expect(doc.at("PmtInf/ReqdExctnDt").text).to eq("2026-10-14")
    expect(doc.at("PmtInf/DbtrAcct/Id/IBAN").text).to eq(bank.iban)
    expect(doc.xpath("//CdtTrfTxInf/PmtId/EndToEndId").map(&:text)).to eq(two.items.order(:id).map(&:end_to_end_id))
    expect(doc.at("GrpHdr/CtrlSum").text).to eq(format("%.2f", two.total))
  end

  it "writes the account paid as it was when the batch was made, the name of the holder and the free remittance" do
    doc = xml
    item = batch.items.first

    expect(doc.at("CdtTrfTxInf/CdtrAcct/Id/IBAN").text).to eq("BE68539007547034")
    expect(doc.at("CdtTrfTxInf/Cdtr/Nm").text).to eq(item.holder_name)
    expect(doc.at("CdtTrfTxInf/Amt/InstdAmt").text).to eq("1210.00")
    expect(doc.at("CdtTrfTxInf/Amt/InstdAmt")["Ccy"]).to eq("EUR")
    expect(doc.at("CdtTrfTxInf/RmtInf/Ustrd").text).to eq(item.remittance)
  end

  it "writes a structured communication in the form people read, as unstructured text (nothing is assumed of the bank beyond that)" do
    batch = batch_of(posted(payment_reference: "+++090/9337/55493+++"))

    expect(xml(batch).at("CdtTrfTxInf/RmtInf/Ustrd").text).to eq("+++090/9337/55493+++")
  end

  it "leaves out a payment that was excluded" do
    other = batch_of(posted(unit_price: 100), posted(partner: create(:partner, :supplier, name: "Beta Corp", iban: nil).tap { |p| create(:partner_bank_account, :verified, partner: p, iban: "BE71096123456769", created_by: owner, first_seen_at: 90.days.ago) }))
    other.items.order(:id).last.update!(status: :excluded, exclusion_reason: "held")
    other.update_columns(total: other.items.included.sum(:amount), payments_count: 1)

    expect(xml(other).xpath("//CdtTrfTxInf").size).to eq(1)
  end

  it "does not guess a version: a profile that names none this builder knows is refused" do
    profile.update!(format_version: "pain.001.001.09")

    expect { build }.to raise_error(Payments::Sepa::UnsupportedVersion, /pain\.001\.001\.09/)
  end

  it "refuses a batch without a bank profile: the version comes from the bank, not from us" do
    batch.update!(bank_profile: nil)

    expect { build }.to raise_error(Payments::Sepa::UnsupportedVersion)
  end

  it "uses only the SEPA character set, whatever the names" do
    supplier.update!(name: "Ædiles Straße")
    account.update_columns(holder_name: "Zoë Ædiles Straße & Fils")
    doc = xml(batch_of(posted))

    expect(doc.at("CdtTrfTxInf/Cdtr/Nm").text).to eq("Zoe AEdiles Strasse   Fils")
  end
end
