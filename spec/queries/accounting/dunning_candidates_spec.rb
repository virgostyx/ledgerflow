require "rails_helper"

# F09 step 1 (docs/dev/features/spec.md §11): which customers are proposed for a reminder, from the open ledger lines (R05, so R04's amounts).
RSpec.describe Accounting::DunningCandidates, type: :query do
  include_context "with open customer lines"

  def rows = described_class.new(as_of: as_of, policy: policy).call
  def row_for(partner) = rows.find { |r| r.partner == partner }

  describe "what is proposed" do
    it "groups the overdue open lines of a customer, with the total, the oldest delay and the way to reach them" do
      a = open_line(amount: 100, days_overdue: 10)
      b = open_line(amount: 50.5, days_overdue: 30)

      expect(rows.sole).to have_attributes(partner: alice, total: BigDecimal("150.5"), oldest_days: 30, channel: "email", recipient: "alice@example.com")
      expect(rows.sole.lines.map(&:line_id)).to contain_exactly(a.id, b.id)
    end

    it "proposes a letter to print for a customer without an e-mail address" do
      open_line(partner: bob)
      expect(row_for(bob)).to have_attributes(channel: "letter", recipient: nil)
    end

    it "puts the customer that is the latest to pay first" do
      open_line(partner: alice, days_overdue: 10)
      open_line(partner: bob, days_overdue: 50)
      expect(rows.map(&:partner)).to eq([ bob, alice ])
    end
  end

  describe "what is never proposed (criterion 1)" do
    {
      "a line in dispute"                  => ->(l) { l.update_columns(disputed: true) },
      "a line under a promise not yet due" => ->(l) { l.update_columns(payment_promised_on: Date.current + 3) },
      "a line promised for today"          => ->(l) { l.update_columns(payment_promised_on: Date.current) }
    }.each do |label, change|
      it "leaves out #{label}" do
        change.call(open_line)
        expect(rows).to be_empty
      end
    end

    it "takes the line back once its promise is past" do
      open_line(payment_promised_on: as_of - 1)
      expect(rows.sole.total).to eq(BigDecimal("100"))
    end

    it "keeps the customer for its other lines when one is disputed or promised" do
      open_line(amount: 100, disputed: true)
      open_line(amount: 40, payment_promised_on: as_of + 5)
      kept = open_line(amount: 25)

      expect(rows.sole.lines.map(&:line_id)).to eq([ kept.id ])
      expect(rows.sole.total).to eq(BigDecimal("25"))
    end

    it "leaves out a customer under the minimum amount of the policy, and keeps one at it" do
      policy.update!(min_amount: 50)
      open_line(partner: alice, amount: 49.99)
      open_line(partner: bob, amount: 50)
      expect(rows.map(&:partner)).to eq([ bob ])
    end

    it "leaves out a line not overdue by the first level's delay (7 days by default)" do
      open_line(days_overdue: 6)
      expect(rows).to be_empty
      open_line(days_overdue: 7)
      expect(rows.sole.total).to eq(BigDecimal("100"))
    end

    it "leaves out the customers marked 'do not remind'" do
      alice.update!(do_not_dun: true)
      open_line
      expect(rows).to be_empty
    end

    it "leaves out a lettered line" do
      line = open_line
      credit = open_line(side: :credit, days_overdue: 1)
      lettering = create(:lettering, account: customer_account, partner: alice)
      Accounting::JournalEntryLine.where(id: [ line.id, credit.id ]).update_all(lettering_id: lettering.id)
      expect(rows).to be_empty
    end

    it "asks only for what is left of a part-paid line" do
      bill    = open_line(amount: 100)
      payment = open_line(amount: 30, side: :credit, days_overdue: 2)
      Accounting::LineAllocation.create!(debit_line: bill, credit_line: payment, amount: 30, allocated_on: as_of)
      expect(rows.sole.total).to eq(BigDecimal("70"))
    end
  end

  describe "the level (criterion 2)" do
    it "is the first level for a line never reminded, however late it is" do
      open_line(days_overdue: 50)
      expect(rows.sole).to have_attributes(level: 1, delay_level: 3)
    end

    it "is the level after the last one sent, once the delay of that level is reached" do
      open_line(days_overdue: 25, dunning_level: 1)
      expect(rows.sole).to have_attributes(level: 2, delay_level: 2)
    end

    it "does not propose a line again until the delay of the next level" do
      open_line(days_overdue: 15, dunning_level: 1)
      expect(rows).to be_empty
    end

    it "waits the minimum days between two reminders (14 by default, as the policy says) even when the next level's delay is reached" do
      open_line(days_overdue: 40, dunning_level: 1, last_dunned_at: (as_of - 13).in_time_zone)
      expect(rows).to be_empty
      policy.update!(min_days_between: 10)
      expect(rows.sole).to have_attributes(level: 2)
    end

    it "does not propose the third level again" do
      open_line(days_overdue: 90, dunning_level: 3)
      expect(rows).to be_empty
    end

    it "follows the delays set by the policy" do
      policy.update!(level_1_days: 5, level_2_days: 10, level_3_days: 15)
      open_line(days_overdue: 12, dunning_level: 1)
      expect(rows.sole).to have_attributes(level: 2)
    end
  end

  describe "the statement of account (criterion 4)" do
    it "lists every open line, due or not, disputed or not, and totals what R04 gives for the customer" do
      open_line(amount: 100, days_overdue: 40)
      open_line(amount: 60, days_overdue: 2, disputed: true)
      open_line(amount: 10, days_overdue: 40, payment_promised_on: as_of + 2)
      credit = open_line(amount: 30, side: :credit, days_overdue: 5) # a credit note not yet allocated: shown, not deducted

      row = rows.sole
      r04 = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: as_of).call.find { |r| r.partner_name == "Alice" }
      expect(row.statement.size).to eq(4)
      expect(row.balance).to eq(r04.total)
      expect(row.total).to eq(BigDecimal("100")) # what is asked for is not reduced by the credit
      expect(row.credits.map(&:line_id)).to eq([ credit.id ])
    end
  end
end
