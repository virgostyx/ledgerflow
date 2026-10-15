require "rails_helper"

# B03c "Vérifier maintenant" and the public page: what can be said of a certificate that was issued, today - is the signature genuine, what does the key say of itself, does
# the chain of anchors still hold to the anchor it names - and what happened since (without amounts or names).
RSpec.describe Integrity::VerifyCertificate do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    Ledger::SigningKeys.generate!
  end

  def post_entry(date: fiscal_year.start_date + 10)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: date, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
  end

  let(:certificate) { post_entry && Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "standard")[:certificate] }

  it "is valid when the signature is genuine and the books still hold to the anchor it names" do
    result = described_class.call(certificate)

    expect(result).to have_attributes(state: :valid, signature_valid: true, key_status: "active", revoked: false, chain_intact: true)
    expect(result.since).to eq(entries: 0, in_period: 0)
  end

  it "counts what was validated since, and how much of it is dated inside the period covered" do
    certificate
    post_entry(date: fiscal_year.start_date + 20) # since, and in the period of the year

    result = described_class.call(IntegrityCertificate.last)

    expect(result.since[:entries]).to be >= 1
    expect(result.since[:in_period]).to be >= 1
    expect(result.since[:in_period]).to be <= result.since[:entries]
    expect(result.state).to eq(:valid) # a certificate attests the state at its instant: later entries do not make it false
  end

  it "says that the signature is not valid when the certificate was changed in the database" do
    tamper(:integrity_certificates) { IntegrityCertificate.where(id: certificate.id).update_all(body: certificate.body.sub("standard", "full")) }

    expect(described_class.call(certificate.reload)).to have_attributes(state: :signature_invalid, signature_valid: false)
  end

  it "says that the books no longer hold to the anchor when it was altered" do
    certificate
    tamper(:ledger_anchors) { Ledger::Anchor.where(number: 1).update_all(merkle_root: "e" * 64) }

    expect(described_class.call(certificate)).to have_attributes(state: :chain_changed, chain_intact: false)
  end

  it "tells a key that was retired (still genuine) and one that was revoked, and a revoked certificate" do
    certificate
    Ledger::SigningKeys.rotate!
    expect(described_class.call(certificate)).to have_attributes(state: :valid, key_status: "retired")

    Ledger::SigningKeys.revoke!(certificate.key_id, reason: "copied")
    expect(described_class.call(certificate)).to have_attributes(state: :key_revoked, key_status: "revoked", signature_valid: true)

    Integrity::RevokeCertificate.call(certificate: certificate, user: user, reason: "wrong year")
    expect(described_class.call(certificate.reload)).to have_attributes(state: :revoked, revoked: true)
  end
end
