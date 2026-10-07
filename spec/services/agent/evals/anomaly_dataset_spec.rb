require "rails_helper"

# A08: the anomalies of the second evaluation entity are what they were built to be, and the facts of the cases are what the checks and the reports say.
RSpec.describe Agent::Evals::AnomalyDataset do
  let(:built) { Agent::Evals::Dataset.build! }
  let(:entity) { built.anomalies }
  let(:facts) { described_class.facts }

  def findings = ActsAsTenant.with_tenant(entity) { Accounting::ConsistencyRun.order(:id).last.findings.to_a }

  it "is a separate entity, which the evaluation users belong to" do
    expect(entity.name).to eq(described_class::ENTITY_NAME)
    expect(entity).not_to eq(built.entity)
    expect(UserEntity.where(entity: entity).count).to eq(2)
  end

  it "holds one anomaly of each kind it was built with, and the invariant I6" do
    expect(findings.map(&:check_id)).to include("C03", "C04", "C05", "C06", "C09", "C12", "C14")
    expect(findings.select { |finding| finding.check_id == "C11" }.map { |finding| finding.data["invariant"] }).to eq([ "I6" ])
  end

  it "has the causes and the figures it says: the facts are what the checks found" do
    by_check = findings.index_by { |finding| finding.check_id == "C11" ? "I6" : finding.check_id }

    expect(BigDecimal(by_check["C04"].data["net"])).to eq(BigDecimal(facts["an_c04_balance"]))
    expect(BigDecimal(by_check["C05"].data["total"])).to eq(BigDecimal(facts["an_duplicate_total"]))
    expect([ BigDecimal(by_check["C09"].data["booked"]), BigDecimal(by_check["C09"].data["expected"]) ]).to eq([ BigDecimal(facts["an_c09_booked"]), BigDecimal(facts["an_c09_expected"]) ])
    expect(BigDecimal(facts["an_c09_booked"]) - BigDecimal(facts["an_c09_expected"])).to eq(BigDecimal(facts["an_c09_difference"]))
    expect(BigDecimal(by_check["C14"].data["amount"])).to eq(BigDecimal(facts["an_acme_net"]))
    expect(BigDecimal(by_check["I6"].data["difference"]).abs).to eq(BigDecimal(facts["an_unmapped_balance"]))
    expect(by_check["C03"].data["gaps"]).to eq([ facts["an_missing_number"].to_i ])
    expect(by_check["C06"].message).to include("613000")
  end

  it "has a variation whose figures are the facts" do
    result = ActsAsTenant.with_tenant(entity) do
      Accounting::VariationQuery.new(account_prefix: "611", first: Date.new(2026, 1, 1)..Date.new(2026, 3, 31), second: Date.new(2026, 4, 1)..Date.new(2026, 6, 30), group_by: "month").call
    end

    expect([ result.first_total, result.second_total, result.change_total ]).to eq(facts.values_at("an_first_quarter", "an_second_quarter", "an_cost_change").map { |value| BigDecimal(value) })
    expect(result.rows.first).to have_attributes(key: "06", largest_line: BigDecimal(facts["an_oneoff"]))
  end

  it "acknowledges the late-booking anomaly, with the comment the case recalls" do
    ActsAsTenant.with_tenant(entity) do
      late = findings.find { |finding| finding.check_id == "C12" }

      expect(Accounting::ConsistencyAcknowledgement.find_by!(fingerprint: late.fingerprint).comment).to eq(described_class::ACKNOWLEDGEMENT)
    end
  end
end
