require "rails_helper"

# docs/dev/reports/spec.md §8: "figer" a bank reconciliation (R06) records its
# full result, a content hash and who ran it, and is then immutable.
RSpec.describe Accounting::BankReconciliationReport, type: :model do
  include_context "with entity"

  let(:bank_account) { create(:bank_account, entity: entity) }
  let(:user)          { create(:user) }
  let(:result)        { { "b" => "1000.00", "bn" => [], "sn" => [], "gap" => "0.00" } }

  describe ".record!" do
    subject(:report) { described_class.record!(bank_account: bank_account, as_of: Date.new(2026, 3, 31), result: result, user: user) }

    it "persists the result and who ran it" do
      expect(report).to be_persisted
      expect(report.bank_account).to eq(bank_account)
      expect(report.as_of).to eq(Date.new(2026, 3, 31))
      expect(report.result).to eq(result)
      expect(report.user).to eq(user)
      expect(report.entity_id).to eq(entity.id)
    end

    it "computes a SHA-256 hash of the result" do
      expect(report.content_hash).to eq(Digest::SHA256.hexdigest(result.to_json))
    end

    it "gives an identical result the same hash, so re-reading it can be checked for tampering" do
      other = described_class.record!(bank_account: bank_account, as_of: Date.new(2026, 4, 30), result: result, user: user)
      expect(other.content_hash).to eq(report.content_hash)
    end
  end

  describe "immutability" do
    let!(:report) { described_class.record!(bank_account: bank_account, as_of: Date.current, result: result, user: user) }

    it "cannot be updated" do
      expect { report.update(as_of: Date.current - 1) }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end

    it "cannot be deleted" do
      expect { report.destroy }.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end
  end
end
