require "rails_helper"

RSpec.describe Accounting::OverdueReminders, type: :query do
  include_context "with_open_fiscal_year"

  let(:today) { Date.new(2026, 9, 26) }
  let(:alice) { create(:partner, name: "Alice", email: "alice@example.com") }
  let(:bob)   { create(:partner, name: "Bob") }
  let(:user)  { create(:user) }

  def invoice(partner: alice, days_overdue: 10, total: 121, **attrs)
    create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, due_date: today - days_overdue, total_incl_vat: total, **attrs)
  end

  def remind(partner, invoices, level: 1, on: today, status: :sent)
    create(:payment_reminder, partner: partner, level: level, status: status, created_at: on.in_time_zone).tap do |r|
      invoices.each { |i| r.items.create!(invoice: i, amount_due: i.remaining_amount) }
    end
  end

  def rows = described_class.call(as_of: today)

  it "groups the overdue invoices of a customer, with the total still due and the longest delay" do
    a = invoice(days_overdue: 10, total: 100)
    b = invoice(days_overdue: 40, total: 50.5)
    row = rows.sole

    expect(row).to have_attributes(partner: alice, total_due: BigDecimal("150.5"), days_overdue: 40)
    expect(row.invoices).to contain_exactly(a, b)
  end

  it "puts the customer that is the latest to pay first" do
    invoice(partner: alice, days_overdue: 5)
    invoice(partner: bob, days_overdue: 50)
    expect(rows.map(&:partner)).to eq([ bob, alice ])
  end

  describe "what is not overdue or not owed" do
    it "ignores an invoice due today or later" do
      invoice(days_overdue: 0)
      invoice(days_overdue: -5)
      expect(rows).to be_empty
    end

    it "ignores drafts, cancelled and paid invoices" do
      create(:invoice, :draft, partner: alice, fiscal_year: fiscal_year, due_date: today - 10, total_incl_vat: 121)
      create(:invoice, :cancelled, partner: alice, fiscal_year: fiscal_year, due_date: today - 10, total_incl_vat: 121)
      create(:invoice, :paid, partner: alice, fiscal_year: fiscal_year, due_date: today - 10, total_incl_vat: 121)
      expect(rows).to be_empty
    end

    it "ignores supplier invoices, credit notes and invoices without a due date" do
      invoice(invoice_type: :supplier)
      create(:invoice, :posted, partner: alice, fiscal_year: fiscal_year, due_date: today - 10, total_incl_vat: 50, document_type: :credit_note)
      invoice(due_date: nil)
      expect(rows).to be_empty
    end

    it "counts only what is still due of a partly paid invoice, and drops one that is settled" do
      partly = invoice(total: 121, status: :partially_paid)
      settled = invoice(total: 50, status: :partially_paid)
      entry = create(:journal_entry, :draft, journal: create(:journal, :sale), fiscal_year: fiscal_year, entry_date: today)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      account = create(:account, :customer, reconcilable: true)
      create(:journal_entry_line, journal_entry: entry, account: account, invoice: partly, debit: 0, credit: 21)
      create(:journal_entry_line, journal_entry: entry, account: account, invoice: settled, debit: 0, credit: 50)

      expect(rows.sole).to have_attributes(total_due: BigDecimal("100"))
      expect(rows.sole.invoices).to eq([ partly ])
    end
  end

  describe "the level of the next reminder" do
    it "is 1 when the customer was never reminded" do
      invoice
      expect(rows.sole.level).to eq(1)
    end

    it "is the next one after the highest level already sent for its overdue invoices, at most 3" do
      a = invoice
      remind(alice, [ a ], level: 1, on: today - 20)
      expect(rows.sole.level).to eq(2)

      remind(alice, [ a ], level: 3, on: today - 15)
      expect(rows.sole.level).to eq(3)
    end

    it "starts again at 1 when the reminders were for invoices that are no longer overdue" do
      old = invoice(days_overdue: 60, status: :paid)
      remind(alice, [ old ], level: 2, on: today - 30)
      invoice(days_overdue: 3)
      expect(rows.sole.level).to eq(1)
    end
  end

  describe "the delay between two reminders (14 days)" do
    it "makes a customer reminded less than 14 days ago not remindable, and tells when it was" do
      a = invoice
      reminder = remind(alice, [ a ], on: today - 13)
      row = rows.sole

      expect(row.remindable).to be false
      expect(row.last_reminder).to eq(reminder)
    end

    it "makes a customer reminded 14 days ago remindable again" do
      a = invoice
      remind(alice, [ a ], on: today - 14)
      expect(rows.sole.remindable).to be true
    end

    it "does not count a reminder that failed to go out" do
      a = invoice
      remind(alice, [ a ], on: today - 1, status: :failed)
      row = rows.sole
      expect(row.remindable).to be true
      expect(row.level).to eq(1)
      expect(row.last_reminder).to be_nil
    end

    it "counts a reminder still waiting to be sent" do
      a = invoice
      remind(alice, [ a ], on: today - 1, status: :queued)
      expect(rows.sole.remindable).to be false
    end
  end

  it "is remindable by e-mail only for a customer that has an address" do
    invoice(partner: alice)
    invoice(partner: bob)
    expect(rows.to_h { |r| [ r.partner.name, r.email.present? ] }).to eq("Alice" => true, "Bob" => false)
  end
end
