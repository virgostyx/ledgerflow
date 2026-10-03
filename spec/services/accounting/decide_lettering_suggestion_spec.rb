require "rails_helper"

# F04 §7: accepting a suggestion letters its lines (for real, through LetterLines); rejecting keeps it out.
RSpec.describe "Deciding a lettering suggestion" do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)     { create(:user, role: :accountant) }
  let(:supplier) { create(:partner, :supplier) }
  let(:od)       { create(:journal, :cash) }

  def line(debit: 0, credit: 0)
    ApplicationRecord.transaction do
      entry = create(:journal_entry, status: :posted, journal: od, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 20)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account_604, debit: BigDecimal(credit.to_s), credit: BigDecimal(debit.to_s))
      create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
    end
  end

  let!(:a) { line(credit: 121) }
  let!(:b) { line(debit: 121) }
  let(:suggestion) { Accounting::SuggestLetterings.call; Accounting::LetteringSuggestion.proposed.sole }

  describe Accounting::AcceptLetteringSuggestion do
    it "letters the lines and records who decided" do
      expect(described_class.call(suggestion: suggestion, user: user)).to be_success

      expect(a.reload.lettering_id).to be_present
      expect(suggestion.reload).to be_accepted
      expect(suggestion).to have_attributes(decided_by_id: user.id)
      expect(suggestion.decided_at).to be_present
      expect(Accounting::Lettering.find(a.lettering_id).auto).to be(false)
    end

    it "marks an automatic lettering as such" do
      described_class.call(suggestion: suggestion, user: nil, auto: true)

      expect(Accounting::Lettering.find(a.reload.lettering_id).auto).to be(true)
    end

    it "fails cleanly, leaving the suggestion proposed, when a line has been lettered meanwhile" do
      s = suggestion
      Accounting::LetterLines.call(lines: [ a, b ])

      expect(described_class.call(suggestion: s, user: user)).to be_failure
      expect(s.reload).to be_proposed
    end

    it "refuses a suggestion that was already decided" do
      s = suggestion
      described_class.call(suggestion: s, user: user)

      expect(described_class.call(suggestion: s, user: user)).to be_failure
    end
  end

  describe "rejecting" do
    it "keeps the suggestion out of the proposals" do
      suggestion.reject!(user)
      Accounting::SuggestLetterings.call

      expect(Accounting::LetteringSuggestion.proposed).to be_empty
      expect(Accounting::LetteringSuggestion.rejected.sole).to have_attributes(decided_by_id: user.id)
    end
  end
end

RSpec.describe Accounting::SuggestLetteringsJob do
  include_context "with_open_fiscal_year"

  it "refreshes the suggestions of every entity" do
    other = create(:entity)
    called = []
    allow(Accounting::SuggestLetterings).to receive(:call) { called << ActsAsTenant.current_tenant.id }

    described_class.perform_now

    expect(called).to include(entity.id, other.id)
  end
end
