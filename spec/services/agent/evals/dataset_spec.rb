require "rails_helper"

# A12: the expected figures of the cases are computed from the table of the dataset, by arithmetic. Here they are checked against what the application says of the books built from
# that same table: a disagreement is an error of the application, not of the expectation.
RSpec.describe Agent::Evals::Dataset do
  let(:facts) { described_class.facts }
  let!(:built) { described_class.build! }
  let(:entity) { built.entity }

  def in_entity(&block) = ActsAsTenant.with_tenant(entity, &block)
  def year = in_entity { Accounting::FiscalYear.find_by!(year: 2026) }

  it "is invented: an entity and users that exist for the evaluation only" do
    expect(entity.name).to eq("Agent Evaluation Demo")
    expect([ built.accountant.email, built.reader.email ]).to all(end_with("@ledgerflow.test"))
  end

  it "is built once: the next call finds it" do
    expect { described_class.build! }.not_to change(Entity, :count)
    expect(described_class.build!.entity).to eq(entity)
  end

  it "has the figures its table says: the aged balance of customers and suppliers" do
    in_entity do
      customers = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: described_class::AS_OF).call
      suppliers = Accounting::AgedBalanceQuery.new(kind: :supplier, as_of: described_class::AS_OF).call
      customer_totals = Accounting::AgedBalanceQuery.totals(customers)

      expect(Agent::ToolResult.money(customer_totals.total)).to eq(facts["customers_total"])
      expect(Agent::ToolResult.money(customer_totals.overdue)).to eq(facts["customers_overdue"])
      expect(customers.to_h { |row| [ row.partner_name, Agent::ToolResult.money(row.total) ] }).to include("Acme SA" => facts["acme_total"], "Bravo SRL" => facts["bravo_total"], "Charlie Dupont" => facts["charlie_total"])
      expect(Agent::ToolResult.money(Accounting::AgedBalanceQuery.totals(suppliers).total)).to eq(facts["suppliers_total"])
      expect(Agent::ToolResult.money(Accounting::AgedBalanceQuery.totals(suppliers).overdue)).to eq(facts["suppliers_overdue"])
    end
  end

  it "has the lines older than 60 days its table says" do
    in_entity do
      rows = Accounting::UnletteredLinesQuery.new(kind: :customer, as_of: described_class::AS_OF, min_age_days: 61).call

      expect(rows.size.to_s).to eq(facts["over_60_lines"])
      expect(Agent::ToolResult.money(rows.sum(&:residual))).to eq(facts["over_60_total"])
    end
  end

  it "has the trial balance its table says: revenue, expenses, and a balanced whole" do
    in_entity do
      rows = Accounting::TrialBalanceQuery.new(fiscal_year: year, as_of: described_class::AS_OF).call.index_by(&:code)

      expect(Agent::ToolResult.money(rows.fetch("700000").balance)).to eq(facts["revenue"])
      expect(Agent::ToolResult.money(rows.fetch("600000").balance)).to eq(facts["expenses"])
      expect(Agent::ToolResult.money(rows.values.sum(&:total_debit))).to eq(facts["trial_balance_debit_total"])
      expect(rows.values.sum(&:total_debit)).to eq(rows.values.sum(&:total_credit))
    end
  end

  it "has the VAT its table says, for the year and for the third quarter" do
    in_entity do
      grids = Accounting::VatGridQuery.call(fiscal_year_id: year.id, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 9, 30))

      expect(grids.values.map { |amount| Agent::ToolResult.money(amount) }).to include(facts["q3_vat_collected"], facts["q3_vat_deductible"])
    end
  end

  it "has the indicators its table says" do
    in_entity do
      cards = Accounting::DashboardKpis.new(fiscal_year: year, as_of: described_class::AS_OF).call.index_by { |card| card.key.to_s }

      expect(Agent::ToolResult.money(cards.fetch("revenue_ytd").value)).to eq(facts["revenue"])
      expect(Agent::ToolResult.money(cards.fetch("result_ytd").value)).to eq(facts["result"])
      expect(Agent::ToolResult.money(cards.fetch("overdue_receivables").value)).to eq(facts["customers_overdue"])
    end
  end

  it "has a natural person among its customers, a document, and a run of the consistency checks" do
    in_entity do
      expect(Accounting::Partner.find_by!(name: "Charlie Dupont").is_natural_person).to be true
      expect(Accounting::Partner.where(is_natural_person: false).count).to eq(4)
      expect(Accounting::Document.count).to eq(1)
      expect(Accounting::ConsistencyRun.count).to eq(1)
    end
  end
end
