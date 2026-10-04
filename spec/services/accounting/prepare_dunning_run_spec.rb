require "rails_helper"

# F09 step 2: preparing a run makes items, sends nothing (criterion 3 starts here: a prepared item is only a proposal).
RSpec.describe Accounting::PrepareDunningRun do
  include_context "with open customer lines"

  let(:user) { create(:user) }

  def prepare(**) = described_class.call(user: user, on: as_of, **)

  it "makes a prepared run with one pending item per customer, its lines, its amounts and its text, and sends nothing" do
    a = open_line(amount: 100, days_overdue: 30)
    b = open_line(amount: 50.5, days_overdue: 10)
    open_line(partner: bob, amount: 80, days_overdue: 8)

    expect { prepare }.not_to(change { ActionMailer::Base.deliveries.size })
    run = Accounting::DunningRun.sole
    item = run.items.find_by!(partner: alice)

    expect(run).to have_attributes(status: "prepared", created_by: user, run_on: as_of)
    expect(run.items.map(&:partner)).to contain_exactly(alice, bob)
    expect(item).to have_attributes(status: "pending", level: 1, proposed_level: 1, total: BigDecimal("150.5"), channel: "email",
                                    recipient: "alice@example.com", language: "fr", excluded: false)
    expect(item.item_lines.map(&:line_id)).to contain_exactly(a.id, b.id)
    expect(item.item_lines.sum(&:amount)).to eq(item.total)
    expect(item.subject).to eq("Rappel de paiement")
    expect(item.body).to include("Alice", "150,50", "30")
    expect(run.items.find_by!(partner: bob)).to have_attributes(channel: "letter", recipient: nil)
  end

  it "writes the text in the language of the customer" do
    alice.update!(language: "nl")
    open_line
    expect(prepare[:run].items.sole.subject).to eq("Betalingsherinnering")
  end

  it "adds the charges of the policy to the item, and nothing when the policy has none" do
    open_line(amount: 1000, days_overdue: 73)
    expect(prepare[:run].items.sole).to have_attributes(fees: 0, interest: 0, indemnity: 0)
  end

  it "adds the fee, the interest and the indemnity of the policy, and says so in the text" do
    policy.update!(fee_1: 5, interest_enabled: true, interest_rate: 10, indemnity_enabled: true, indemnity_amount: 40)
    open_line(amount: 1000, days_overdue: 73)
    item = prepare[:run].items.sole

    expect(item).to have_attributes(fees: BigDecimal("5"), interest: BigDecimal("20"), indemnity: BigDecimal("40"), total: BigDecimal("1000"))
    expect(item.grand_total).to eq(BigDecimal("1065"))
    expect(item.body).to include("1 065,00")
  end

  it "has nothing to prepare when nobody is proposed" do
    open_line(days_overdue: 2)
    result = prepare
    expect(result).to be_failure
    expect(result.message).to eq("Nobody has to be reminded today.")
    expect(Accounting::DunningRun.count).to eq(0)
  end

  describe "two campaigns the same day for a customer (criterion 7)" do
    it "refuses the second, and says where the first is" do
      open_line
      first = prepare[:run]
      open_line(partner: bob)

      second = prepare
      expect(second[:refused].map { |r| [ r[:partner], r[:item].run ] }).to eq([ [ alice, first ] ])
      expect(second[:run].items.map(&:partner)).to eq([ bob ])
    end

    it "fails with the link to the first campaign when nobody else is left" do
      open_line
      first = prepare[:run]
      result = prepare
      expect(result).to be_failure
      expect(result[:refused].sole[:item].run).to eq(first)
      expect(Accounting::DunningRun.count).to eq(1)
    end

    it "lets the customer be prepared again the day after" do
      open_line
      prepare
      expect(described_class.call(user: user, on: as_of + 1)).to be_success
    end

    it "does not count an item that was left out of its run" do
      open_line
      prepare[:run].items.sole.update!(excluded: true)
      expect(prepare).to be_success
    end

    it "is also refused by the database" do
      open_line
      item = prepare[:run].items.sole
      other_run = Accounting::DunningRun.create!(run_on: as_of)
      expect { item.dup.tap { |i| i.run = other_run }.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
