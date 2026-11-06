require "rails_helper"

RSpec.describe Accounting::BankReconciliationQuery::Result do
  describe "#to_snapshot" do
    it "serialises amounts and dates as strings, ready to be frozen as JSON" do
      item = Accounting::BankReconciliationQuery::Item.new(date: Date.new(2026, 3, 30), label: "Cheque 12", amount: BigDecimal("12.5"))
      result = described_class.new(statement_balance: BigDecimal("100"), accounting_balance: BigDecimal("87.5"),
                                   bn: [ item ], sn: [], bn_total: BigDecimal("12.5"), sn_total: BigDecimal("0"),
                                   expected_balance: BigDecimal("112.5"), gap: BigDecimal("-25"))

      expect(result.to_snapshot).to eq(
        statement_balance: "100.0", accounting_balance: "87.5", bn_total: "12.5", sn_total: "0.0",
        expected_balance: "112.5", gap: "-25.0",
        bn: [ { date: "2026-03-30", label: "Cheque 12", amount: "12.5" } ], sn: []
      )
    end
  end
end
