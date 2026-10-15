require "rails_helper"

# B03c étape 3, critère 7: the fingerprint of an anchor is sent to a timestamp authority (RFC 3161), the token it answers is checked against its certificate and kept in the
# anchor, once; only the fingerprint leaves the application. An authority that does not answer, or answers wrongly, leaves the anchor without a token, and a job tries again.
RSpec.describe Ledger::Timestamping do
  include_context "with_open_fiscal_year"
  include_context "with a timestamp authority"

  let(:journal) { create(:journal, :purchase) }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  def post_entry
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: 10, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: 10)
    Accounting::PostJournalEntry.call!(entry: entry)
  end

  let(:anchor) { post_entry && Ledger::Anchoring.call(kind: "nightly") }

  def configure(url: "https://tsa.example.test/tsr", ca: authority.ca_pem) = entity.update!(timestamp_authority_url: url, timestamp_authority_ca: ca)

  it "does nothing when no authority is configured, and says so" do
    expect(described_class.call(anchor, transport: authority.transport)).to eq(:off)
    expect(anchor.reload.timestamp_token).to be_nil
    expect(authority.queries).to be_empty
  end

  it "asks the authority for the token of the fingerprint of the anchor, checks it, and keeps it with the authority and the time" do
    configure

    expect(described_class.call(anchor, transport: authority.transport)).to eq(:granted)

    anchor.reload
    expect(anchor).to have_attributes(timestamp_authority: "https://tsa.example.test/tsr", timestamp_error: nil)
    expect(anchor.timestamp_token).to be_present
    expect(anchor.timestamped_at).to be_within(1.minute).of(Time.current)
    expect(LedgerVerify::Verifier.send(:verify_token, anchor.timestamp_token, anchor.anchor_hash, authority.ca_pem).first).to be(true)
    expect(LedgerVerify::Verifier.send(:verify_token, anchor.timestamp_token, "0" * 64, authority.ca_pem).first).to be(false) # another fingerprint: another timestamp
  end

  it "sends the fingerprint and nothing of the books" do
    configure
    described_class.call(anchor, transport: authority.transport)

    query = authority.queries.sole
    expect(query.bytesize).to be < 120
    expect(query.b).to include([ anchor.anchor_hash ].pack("H*"))
    expect(query.b).not_to include(entity.legal_name.b)
  end

  it "keeps the token once: a second call does not ask again" do
    configure
    described_class.call(anchor, transport: authority.transport)

    expect(described_class.call(anchor, transport: authority.transport)).to eq(:already)
    expect(authority.queries.size).to eq(1)
  end

  it "leaves the anchor without token when the authority does not answer, and says why" do
    configure

    expect(described_class.call(anchor, transport: authority.transport(unavailable: true))).to eq(:unavailable)

    expect(anchor.reload.timestamp_token).to be_nil
    expect(anchor.timestamp_error).to include("does not answer")
  end

  it "refuses an answer that the certificate configured does not vouch for (another authority, or the answer of an attacker)" do
    configure(ca: TestTimestampAuthority.new.ca_pem)

    expect(described_class.call(anchor, transport: authority.transport)).to eq(:rejected)

    expect(anchor.reload.timestamp_token).to be_nil
    expect(anchor.timestamp_error).to match(/verif/i)
  end

  it "refuses an answer made for another fingerprint" do
    configure
    other = post_entry && Ledger::Anchoring.call(kind: "nightly")
    stale = authority.reply(OpenSSL::Digest.new("sha256").then { |d| `openssl ts -query -digest #{other.anchor_hash} -sha256 -cert` })

    expect(described_class.call(anchor, transport: ->(_url, _query) { stale })).to eq(:rejected)
  end

  it "refuses an address that is not http(s)" do
    configure(url: "file:///etc/passwd")

    expect(described_class.call(anchor, transport: authority.transport)).to eq(:off)
  end

  describe "trying again" do
    it "gives a token to the anchors that have none, when the authority answers again" do
      configure
      described_class.call(anchor, transport: authority.transport(unavailable: true))

      described_class.retry_pending(transport: authority.transport)

      expect(anchor.reload.timestamp_token).to be_present
      expect(anchor.timestamp_error).to be_nil
    end
  end

  describe "in the nightly anchoring" do
    it "timestamps the anchor it makes, when the authority is configured and answers" do
      entity.update!(features: entity.features.merge("b03c" => true))
      configure
      post_entry
      allow(Ledger::Timestamping).to receive(:default_transport).and_return(authority.transport)

      Ledger::NightlyAnchoring.call

      expect(Ledger::Anchor.last.timestamp_token).to be_present
    end
  end
end
