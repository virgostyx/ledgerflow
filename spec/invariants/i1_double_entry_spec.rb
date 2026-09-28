require "rails_helper"

# I1 (docs/dev/reports/spec.md §2.3): Σ débit = Σ crédit, globalement et pour
# chaque écriture. Run on the reference ledger and on random balanced
# registers, per §15.
RSpec.describe "Invariant I1 — Σ débit = Σ crédit", type: :invariant do
  it "holds globally and per entry on the reference ledger" do
    entity = Seeders::ReferenceLedgerSeeder.call

    ActsAsTenant.with_tenant(entity) do
      lines = Accounting::JournalEntryLine.all
      expect(lines.sum(:debit)).to eq(lines.sum(:credit))

      Accounting::JournalEntryLine.group(:journal_entry_id).sum(:debit).each do |entry_id, debit|
        credit = Accounting::JournalEntryLine.where(journal_entry_id: entry_id).sum(:credit)
        expect(debit).to eq(credit), "entry ##{entry_id} is unbalanced: debit=#{debit} credit=#{credit}"
      end
    end
  end

  it "holds on 100 random balanced registers (seed logged to replay a failure)" do
    seed = Random.new_seed
    rng  = Random.new(seed)

    entity = create(:entity)
    ActsAsTenant.with_tenant(entity) do
      journal     = create(:journal, :purchase)
      fiscal_year = create(:fiscal_year, entity: entity)
      accounts    = create_list(:account, 4, entity: entity)

      100.times do |i|
        entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                        entry_date: fiscal_year.start_date + i)
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        amount = BigDecimal(rng.rand(1..100_000).to_s) / 100
        debit_account, credit_account = accounts.sample(2, random: rng)
        create(:journal_entry_line, journal_entry: entry, account: debit_account, debit: amount, credit: 0)
        create(:journal_entry_line, journal_entry: entry, account: credit_account, debit: 0, credit: amount)
        entry.post!
      rescue StandardError => e
        raise "I1 failed on random register ##{i} (seed=#{seed}): #{e.message}"
      end

      lines = Accounting::JournalEntryLine.all
      expect(lines.sum(:debit)).to eq(lines.sum(:credit)), "seed=#{seed}"
    end
  end
end
