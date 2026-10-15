require "rails_helper"

# B03c: after any sequence of operations - entries validated, reversed, lettered, unlettered, accounts renamed, anchors made at any moment, keys rotated, certificates issued
# and revoked - the proofs hold. The seed of a failing sequence is in the message: replay it.
#
#  I17.  The chain of anchors holds: each root is that of the fingerprints of its entries, the ranges are contiguous, the links unbroken.
#  F.    Every validated entry still gives its fingerprint from its content, and what changes legitimately (status, lettering, residual, names) does not change it.
#  A.    The audit chain holds, whatever was written in it.
#  C.    Every certificate issued still verifies - its signature, and the books holding to the anchor it names - whatever was done since, and its package passes `ledger-verify`.
RSpec.describe "Invariant I17 - the proofs hold after random sequences" do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  seeds = (1..10).to_a
  operations = 20

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:revenue) { create(:account, code: "700000", account_type: :revenue, normal_balance: :credit, account_class: 7) }
  let!(:customer_account) { create(:account, :customer, reconcilable: true) }
  let!(:partner) { create(:partner, name: "Alice") }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    Ledger::SigningKeys.generate!
  end

  def post_entry(lines)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - 3, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    made = lines.map { |attrs| create(:journal_entry_line, journal_entry: entry, **attrs) }
    Current.set(user: user) { Accounting::PostJournalEntry.call!(entry: entry) }
    [ entry.reload, made ]
  end

  def operation(rng, state)
    case rng.rand(12)
    when 0..2
      amount = BigDecimal([ 25, 60, 100, 250 ].sample(random: rng).to_s)
      entry, lines = post_entry([ { account: customer_account, partner: partner, debit: amount, credit: 0 }, { account: revenue, debit: 0, credit: amount } ])
      state[:entries] << entry
      state[:lines] << lines.first
    when 3
      amount = BigDecimal([ 10, 40 ].sample(random: rng).to_s)
      state[:entries] << post_entry([ { account: expense, debit: amount, credit: 0 }, { account: revenue, debit: 0, credit: amount } ]).first
    when 4
      entry = state[:entries].map(&:reload).select(&:posted?).sample(random: rng)
      Accounting::ReverseJournalEntry.call(entry: entry, reason: "random", user: user) if entry
    when 5 then expense.update!(label_fr: "Services #{rng.rand(1000)}")
    when 6 then Accounting::LetterLines.call(lines: state[:lines].map(&:reload).select { |l| l.lettering_id.nil? }.first(1), user: user) if state[:lines].any?
    when 7 then Ledger::Anchoring.call(kind: rng.rand(2).zero? ? "nightly" : "on_demand")
    when 8 then Ledger::SigningKeys.rotate! if rng.rand(3).zero?
    when 9 then state[:certificates] << Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: %w[minimal standard full].sample(random: rng))[:certificate]
    when 10 then Integrity::RevokeCertificate.call(certificate: state[:certificates].sample(random: rng), user: user, reason: "random") if state[:certificates].any?
    else Accounting::AuditLog.record!(auditable: fiscal_year, action: "something_happened", user: user)
    end
  end

  def check!(seed, step, state)
    where = "seed #{seed}, after operation #{step}"
    anchors = Ledger::AnchorChain.verify(entity)
    expect(anchors).to be_intact, "I17 #{where}: anchor #{anchors.broken_number} - #{anchors.reason}"
    findings = Integrity::SelfCheck.call(mode: :full).findings
    expect(findings).to be_empty, "F #{where}: #{findings.map(&:message)}"
    expect(Accounting::AuditVerifier.call(entity: entity)).to be_intact, "A #{where}: the audit chain is broken"
    state[:certificates].reject(&:revoked?).each do |certificate|
      result = Integrity::VerifyCertificate.call(certificate.reload)
      expect(result.state).to eq(:valid), "C #{where}: certificate #{certificate.uuid} is #{result.state}"
    end
  end

  seeds.each do |seed|
    it "holds for seed #{seed}" do
      rng = Random.new(seed)
      state = { entries: [], lines: [], certificates: [] }
      operations.times do |step|
        operation(rng, state)
        next_posting_instant
        check!(seed, step, state)
      end
      full = state[:certificates].find { |c| c.disclosure_level == "full" && !c.revoked? }
      next unless full

      report = LedgerVerify::Verifier.call(Integrity::BuildPackage.call(certificate: full.reload).data)
      expect(report).to be_pass, "seed #{seed}: ledger-verify says #{report.failures.map(&:message)}"
    end
  end
end
