require "rails_helper"

# A04: what a person types to the agent may hold what must not leave: a bank number, a national number, a card, a password. They are told before anything is sent.
RSpec.describe Agent::SensitiveInput do
  include_context "with entity"

  let(:setting) { Agent::Setting.for_current_entity }
  let(:iban) { "BE68539007547034" }
  let(:national_number) { "850731001#{format('%02d', 97 - 850731001 % 97)}" }
  let(:card) { "4111 1111 1111 1111" }

  def review(text) = described_class.review(text, setting)

  it "finds nothing in an ordinary question" do
    expect(review("What does Alice Dupont owe me at 31/12 on account 400000, invoice 2026-0042?")).to be_clear
  end

  it "finds an IBAN, and says it will be masked by default" do
    found = review("My account is #{iban}")

    expect(found.findings.map { |f| [ f.kind, f.effect ] }).to eq([ [ :iban, :mask ] ])
    expect(found).not_to be_blocked
  end

  it "finds a national number, masked by default as it is a personal identifier" do
    expect(review("born #{national_number}").findings.map { |f| [ f.kind, f.effect ] }).to eq([ [ :national_number, :mask ] ])
  end

  it "follows the mode of the entity: sent as it is, masked, or impossible" do
    setting.update!(data_class_modes: { "bank_identifier" => "send", "personal" => "block" })

    expect(review(iban).findings.first.effect).to eq(:send)
    expect(review(national_number).findings.first.effect).to eq(:block)
    expect(review(national_number)).to be_blocked
  end

  it "always refuses a bank card number and a password, whatever the settings" do
    setting.update!(data_class_modes: { "bank_identifier" => "send", "personal" => "send" })

    expect(review("card #{card}").findings.map { |f| [ f.kind, f.effect ] }).to eq([ [ :card, :block ] ])
    expect(review("mot de passe: Tr0ub4dor&3").findings.map { |f| [ f.kind, f.effect ] }).to eq([ [ :password, :block ] ])
    expect(review("password = hunter2")).to be_blocked
  end

  it "does not take a long number that is not a card for one" do
    expect(review("amount 4111 1111 1111 1112")).to be_clear
  end

  it "counts what it found, and never keeps the value" do
    found = review("#{iban} and BE71096123456769 and card #{card}")

    expect(found.findings.map { |f| [ f.kind, f.count ] }).to contain_exactly([ :iban, 2 ], [ :card, 1 ])
    expect(found.findings.to_s).not_to include("BE68", "4111")
  end
end
