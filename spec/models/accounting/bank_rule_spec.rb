require "rails_helper"

RSpec.describe Accounting::BankRule do
  include_context "with entity"

  let(:account) { create(:account, code: "651100") }
  let(:bank_account) { create(:bank_account) }

  def rule(**attrs) = described_class.new({ name: "R", condition_type: "contains", condition_value: "x", account: account }.merge(attrs))
  def line(**attrs) = create(:bank_transaction, bank_account: bank_account, amount: -10, **attrs)

  describe "validation" do
    it "needs a name, a known condition and action, and a score from 1 to 99" do
      expect(rule).to be_valid
      expect(rule(name: "")).not_to be_valid
      expect(rule(condition_type: "regex")).not_to be_valid
      expect(rule(action: "post")).not_to be_valid
      expect(rule(score: 100)).not_to be_valid
      expect(rule(score: 0)).not_to be_valid
    end

    it "wants a number as the value of an amount condition" do
      expect(rule(condition_type: "amount", condition_value: "12,50")).to be_valid
      expect(rule(condition_type: "amount", condition_value: "abc")).not_to be_valid
    end
  end

  describe "#matches?" do
    it "finds a text in the counterparty or the communication, ignoring case and accents" do
      expect(rule(condition_value: "société").matches?(line(counterparty_name: "SOCIETE GENERALE"))).to be true
      expect(rule(condition_value: "loyer mars").matches?(line(description: "LOYER MARS 2026"))).to be true
      expect(rule(condition_value: "assurance").matches?(line(description: "loyer"))).to be false
    end

    it "compares an IBAN whatever its spacing or case" do
      iban = CodaBuilder.iban("091012345678")

      expect(rule(condition_type: "iban", condition_value: iban.scan(/.{1,4}/).join(" ").downcase).matches?(line(counterparty_iban: iban))).to be true
      expect(rule(condition_type: "iban", condition_value: CodaBuilder.iban("001234567890")).matches?(line(counterparty_iban: iban))).to be false
    end

    it "compares the exact signed amount" do
      expect(rule(condition_type: "amount", condition_value: "-10").matches?(line)).to be true
      expect(rule(condition_type: "amount", condition_value: "10").matches?(line)).to be false
    end
  end

  describe ".from_line" do
    it "builds an IBAN rule from a line that has one, a text rule from the name or the communication otherwise" do
      with_iban = described_class.from_line(line(counterparty_iban: CodaBuilder.iban("091012345678")), account: account, name: "R")
      with_name = described_class.from_line(line(counterparty_name: "BUREAU PLUS SA"), account: account, name: "R")
      with_text = described_class.from_line(line(description: "ASSURANCE AUTO"), account: account, name: "R")

      expect(with_iban).to have_attributes(condition_type: "iban")
      expect(with_name).to have_attributes(condition_type: "contains", condition_value: "BUREAU PLUS SA")
      expect(with_text).to have_attributes(condition_value: "ASSURANCE AUTO")
    end
  end

  describe ".first_match_for" do
    it "returns the first active rule by priority that matches, or nil" do
      later = described_class.create!(name: "later", condition_type: "contains", condition_value: "x", account: account, priority: 50)
      sooner = described_class.create!(name: "sooner", condition_type: "contains", condition_value: "x", account: account, priority: 5)

      expect(described_class.first_match_for(line(description: "x"))).to eq(sooner)
      expect(later).to be_persisted
      expect(described_class.first_match_for(line(description: "nothing"))).to be_nil
    end
  end
end
