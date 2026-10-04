require "rails_helper"

RSpec.describe Seeders::ReferenceLedgerSeeder do
  subject(:entity) { described_class.call }

  it "creates a balanced ledger covering every P0 scenario" do
    ActsAsTenant.with_tenant(entity) do
      lines = Accounting::JournalEntryLine.all
      expect(lines.sum(:debit)).to eq(lines.sum(:credit)) # invariant I1

      expect(Accounting::FiscalYear.pluck(:year, :status)).to contain_exactly([ 2025, "closed" ], [ 2026, "open" ])
      expect(Accounting::Invoice.count).to be >= 8 # sales/purchases + special VAT + credit note
      expect(Accounting::Lettering.count).to eq(3) # full + grouped + the sale in USD paid at another rate (F11)
      expect(Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::FX_SOURCE).count).to eq(1) # its exchange difference
      expect(Accounting::LineAllocation.count).to be >= 1 # partial
      expect(Accounting::BankAccount.count).to eq(2)
      expect(Accounting::BankTransaction.where(journal_entry_id: nil)).not_to be_empty # SN
    end
  end

  it "is idempotent" do
    entity
    expect { described_class.call }.not_to(change { ActsAsTenant.with_tenant(entity) { Accounting::JournalEntryLine.count } })
  end
end
