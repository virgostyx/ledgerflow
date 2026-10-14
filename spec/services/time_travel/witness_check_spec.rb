require "rails_helper"

# B03a §"Témoins de vérité" (critères 2 and 12): the snapshots that were frozen are recomputed at the instant they were taken, from the history, and compared. A difference
# is a blocking anomaly of R19 (C20).
RSpec.describe TimeTravel::WitnessCheck do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user) }
  let!(:expense) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit, account_class: 4) }
  let!(:vat_account) { create(:account, code: "451000", label_fr: "VAT to pay") }

  before { Accounting::HistoryStart.create!(starts_at: 1.day.ago) }

  def post_entry(amount, vat: nil)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: "W-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0, **(vat ? { vat_code: 1, vat_amount: vat } : {}))
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount)
    entry.post!
    next_posting_instant
    entry
  end

  def filed_grids
    grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id, period_start: fiscal_year.start_date, period_end: fiscal_year.start_date + 89)
    grids.merge(Accounting::VatGrid.balance(grids)).sort.to_h.transform_values { |v| format("%.2f", v) }
  end

  def snapshot!
    run = Accounting::ClosingRun.create!(fiscal_year: fiscal_year, opened_by: user, status: :closed)
    content = Closing::SnapshotContent.call(fiscal_year: fiscal_year)
    Accounting::ClosingSnapshot.create!(run: run, content: content, sha256: Accounting::ClosingSnapshot.fingerprint(content)).tap { next_posting_instant }
  end

  it "finds nothing when the history reproduces the snapshots, even after the books moved on" do
    post_entry(BigDecimal("100"))
    snapshot!
    post_entry(BigDecimal("40")) # after the snapshot: the books are no longer the same today, and were at the instant of the snapshot

    expect(described_class.call).to be_empty
  end

  it "finds a snapshot that the history does not reproduce" do
    post_entry(BigDecimal("100"))
    snapshot = snapshot!
    forged = snapshot.content.deep_dup
    forged["trial_balance"].first["debit"] = "999.00"
    snapshot.update_columns(content: forged, sha256: Accounting::ClosingSnapshot.fingerprint(forged))

    divergence = described_class.call.sole

    expect(divergence).to have_attributes(witness_type: "Accounting::ClosingSnapshot", witness_id: snapshot.id)
    expect(divergence.detail).to include("trial_balance")
  end

  it "recomputes the VAT returns that were filed from the grids they carry" do
    post_entry(BigDecimal("1000"), vat: BigDecimal("210"))
    declaration = Accounting::VatDeclaration.create!(fiscal_year: fiscal_year, status: :submitted, period_type: :quarterly, period_start: fiscal_year.start_date, period_end: fiscal_year.start_date + 89,
                                                     grids: filed_grids)
    next_posting_instant
    post_entry(BigDecimal("1000"), vat: BigDecimal("105"))

    expect(described_class.call).to be_empty

    declaration.update_columns(grids: declaration.grids.merge("01" => "1.00"))
    expect(described_class.call.sole).to have_attributes(witness_type: "Accounting::VatDeclaration", witness_id: declaration.id)
  end

  it "does not look at a VAT return that is still a draft" do
    post_entry(BigDecimal("1000"), vat: BigDecimal("210"))
    Accounting::VatDeclaration.create!(fiscal_year: fiscal_year, status: :draft, period_type: :quarterly, period_start: fiscal_year.start_date, period_end: fiscal_year.start_date + 89, grids: { "01" => "1.00" })

    expect(described_class.call).to be_empty
  end

  describe "the anomaly C20 of the consistency checks" do
    it "is blocking, and reports a divergence" do
      post_entry(BigDecimal("100"))
      snapshot = snapshot!
      forged = snapshot.content.deep_dup
      forged["trial_balance"].first["credit"] = "1.00"
      snapshot.update_columns(content: forged, sha256: Accounting::ClosingSnapshot.fingerprint(forged))

      findings = Accounting::Consistency::Checks::C20HistoricalDivergence.new.call

      expect(Accounting::Consistency::Checks::C20HistoricalDivergence.severity).to eq("blocking")
      expect(findings.sole.message).to include("snapshot")
    end

    it "reports nothing when the history holds" do
      post_entry(BigDecimal("100"))
      snapshot!

      expect(Accounting::Consistency::Checks::C20HistoricalDivergence.new.call).to be_empty
    end
  end
end
