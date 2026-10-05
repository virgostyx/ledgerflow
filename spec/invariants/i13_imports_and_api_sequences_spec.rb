require "rails_helper"

# F13: the imports and the API write in the ledger (drafts, then validation and reversal by their services). Random sequences of what they can do, in any
# order, must leave I1 (Σ debit = Σ credit, globally and per entry) and I2 (trial balance nets to zero) true after each step. The seed is in the message of a failure.
RSpec.describe "Invariants I1 and I2 after random imports and API operations", type: :invariant do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:user)     { create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) } }
  let!(:journal) { create(:journal, code: "OD", journal_type: :misc) }

  def assert_invariants(seed, step)
    lines = Accounting::JournalEntryLine.all
    expect(lines.sum(:debit)).to eq(lines.sum(:credit)), "I1 (global) after #{step}, seed=#{seed}"
    Accounting::JournalEntryLine.group(:journal_entry_id).sum(:debit).each do |entry_id, debit|
      expect(debit).to eq(Accounting::JournalEntryLine.where(journal_entry_id: entry_id).sum(:credit)), "I1 (entry ##{entry_id}) after #{step}, seed=#{seed}"
    end
    net = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year).call.sum { |r| r.total_debit - r.total_credit }
    expect(net).to eq(0), "I2 after #{step}, seed=#{seed}"
  end

  def random_file(rng, serial)
    pieces = Array.new(rng.rand(1..6)) do |i|
      amount = rng.rand(1..50_000) / 100.0
      other = rng.rand(10) == 0 ? amount + 1 : amount # one in ten does not balance: refused whole
      [ "S#{serial}-#{i}", (fiscal_year.start_date + rng.rand(0..300)).iso8601, [ [ "604000", format("%.2f", amount), "" ], [ "440000", "", format("%.2f", other) ] ] ]
    end
    entries_csv(pieces)
  end

  it "keeps I1 and I2 through 60 random steps (import, API create, validate, reverse, take back)" do
    seed = Random.new_seed
    rng = Random.new(seed)
    batches = []
    api = ApiClient.issue!(entity: entity, name: "Seq", scopes: %w[entries:write entries:post entries:reverse], owner: user).first

    60.times do |step|
      case rng.rand(5)
      when 0 # a guided import, some pieces refused
        batch = run_import(start_import("entries", random_file(rng, step), user: user), user: user)
        batches << batch if batch.result == "imported"
      when 1 # what the API does for a create: the same build as the controller, as a draft
        entry = Accounting::JournalEntry.new(journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + rng.rand(0..300), status: :draft, created_by: api.owner)
        amount = BigDecimal(rng.rand(1..9_999).to_s)
        entry.lines.build(account: account_604, debit: amount, credit: 0)
        entry.lines.build(account: account_440, debit: 0, credit: amount)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        entry.save!
      when 2 # validate a draft
        draft = Accounting::JournalEntry.draft.order("RANDOM()").first
        Accounting::PostJournalEntry.call(entry: draft) if draft
      when 3 # reverse a validated entry
        posted = Accounting::JournalEntry.posted.where(reversal_of_id: nil).order("RANDOM()").first
        Accounting::ReverseJournalEntry.call(entry: posted, reason: "sequence", user: user) if posted
      when 4 # take an import back (drafts deleted, validated ones reversed)
        batch = batches.delete_at(rng.rand(batches.size)) if batches.any?
        Imports::Undo.call(batch: batch, user: user, reason: "sequence") if batch
      end
      assert_invariants(seed, "step #{step}")
    end
  end
end
