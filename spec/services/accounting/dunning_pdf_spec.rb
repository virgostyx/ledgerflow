require "rails_helper"

# F09 step 4: the letter and the statement of account. The statement's balance is R04's total for the customer (criterion 4).
RSpec.describe Accounting::DunningPdf do
  include_context "with open customer lines"

  let(:user) { create(:user) }
  let(:item) { Accounting::PrepareDunningRun.call(user: user, on: as_of)[:run].items.sole }

  def text(pdf) = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join(" ").gsub(/\s+/, " ")
  def r04_total = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: as_of).call.find { |r| r.partner_name == "Alice" }.total
  def money(amount) = Accounting::MoneyPresenter.new(amount).format

  before do
    open_line(amount: 100, days_overdue: 40)
    open_line(amount: 60, days_overdue: 3)                         # not due long enough to be asked for, still on the statement
    open_line(amount: 25, days_overdue: 20, disputed: true)
    open_line(amount: 30, side: :credit, days_overdue: 5)          # a credit note not allocated
  end

  describe "the statement of account" do
    let(:pdf) { described_class.new(item, letter: false).render }

    it "lists every open line and ends on the balance R04 gives for the customer" do
      expect(text(pdf)).to include("Statement of account", "Alice", money(r04_total))
      expect(r04_total).to eq(BigDecimal("155")) # 100 + 60 + 25 - 30
    end

    it "marks what is in dispute, what is not yet asked for, and the credit that is not deducted" do
      content = text(pdf)
      expect(content).to include("Disputed", "Not due for a reminder", "Credit not allocated: not deducted")
    end

    it "says what is asked for, apart from the balance" do
      expect(text(pdf)).to include("Asked for", money(item.total))
      expect(item.total).to eq(BigDecimal("100"))
    end
  end

  describe "the letter" do
    let(:content) { text(described_class.new(item, letter: true).render) }

    it "carries the text of the item, with the customer and the entity, before the statement" do
      expect(content).to include(item.subject, "Alice", ActsAsTenant.current_tenant.legal_name)
      expect(content.index("Statement of account")).to be > content.index(item.subject)
    end

    it "carries the text as edited" do
      item.update!(body: "Hand written words")
      expect(content).to include("Hand written words")
    end
  end
end
