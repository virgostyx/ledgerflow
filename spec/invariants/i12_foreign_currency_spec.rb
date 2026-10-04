require "rails_helper"

# I12 (docs/dev/features/spec.md §13, criterion 8): with operations in USD and ZMW in the books, the line of a foreign currency agrees with its euros at its
# rate, a document wholly in one currency balances in that currency, and a lettering of foreign lines cancels out in that currency.
RSpec.describe "Invariant I12 — foreign currencies", type: :invariant do
  let!(:entity) { Seeders::ReferenceLedgerSeeder.call }

  def in_entity(&block) = ActsAsTenant.with_tenant(entity, &block)

  it "has operations in USD and in ZMW to hold on to" do
    in_entity { expect(Accounting::JournalEntryLine.where.not(currency: "EUR").distinct.pluck(:currency)).to contain_exactly("USD", "ZMW") }
  end

  it "gives every foreign line the sign of its side, and the euros of its amount at its rate, to the cent" do
    in_entity do
      Accounting::JournalEntryLine.where.not(currency: "EUR").find_each do |line|
        expect(line.amount_currency.positive?).to eq(line.debit.positive?), "line ##{line.id}: the sign of #{line.amount_currency} does not follow its side"
        expected = Fx::Convert.to_eur(line.amount_currency.abs, line.exchange_rate)
        expect((line.debit + line.credit - expected).abs).to be <= BigDecimal("0.01"), "line ##{line.id}: #{line.amount_currency} #{line.currency} at #{line.exchange_rate} is #{expected}"
      end
    end
  end

  it "balances an entry wholly in one currency in that currency" do
    in_entity do
      Accounting::JournalEntry.in_ledger.includes(:lines).find_each do |entry|
        currencies = entry.lines.reject { |l| l.label == "Conversion rounding" }.map(&:currency).uniq
        next unless currencies.size == 1 && currencies.first != "EUR"

        expect(entry.lines.sum { |l| l.amount_currency.to_d }).to eq(0), "entry ##{entry.id} does not balance in #{currencies.first}"
      end
    end
  end

  it "cancels a lettering of foreign lines out in their currency, and in EUR once its exchange difference is in" do
    in_entity do
      foreign_letterings = Accounting::Lettering.joins(:lines).where.not(accounting_journal_entry_lines: { currency: "EUR" }).distinct
      expect(foreign_letterings).not_to be_empty
      foreign_letterings.each do |lettering|
        lines = lettering.lines.includes(:journal_entry)
        own = lines.reject { |l| l.journal_entry.fx_adjustment? }
        expect(own.sum { |l| l.amount_currency.to_d }).to eq(0)
        expect(lines.sum(&:debit)).to eq(lines.sum(&:credit))
      end
    end
  end

  it "books the exchange difference of a lettering in an entry that is in the ledger, balanced, and linked to the lettering" do
    in_entity do
      fx = Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::FX_SOURCE)
      expect(fx).not_to be_empty
      fx.each do |entry|
        expect(entry).to be_posted
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
        expect(entry.lettering).to be_present
      end
    end
  end
end
