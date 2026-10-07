require "rails_helper"

# A12: the evaluation holds no real data, only demonstration data. A real identifier would pass the same check digits as the ones the application looks for, so the files are searched for
# those: any IBAN, national number, company number or card number that checks out must be one of the well-known test values named here.
RSpec.describe "The evaluation holds no real data" do
  FILES = [ *Agent::Evals::Runner::CASE_FILES, Rails.root.join("app/services/agent/evals/dataset.rb") ].freeze
  KNOWN_TEST_IBANS = %w[BE68539007547034].freeze # the example of the IBAN standard, which belongs to nobody
  ALLOWED_EMAIL_DOMAINS = %w[ledgerflow.test evil.example].freeze

  let(:texts) { FILES.to_h { |file| [ File.basename(file), File.read(file) ] } }

  it "has files to look at" do
    expect(FILES.size).to be >= 2
  end

  it "has no IBAN that checks out, but the standard's example" do
    found = texts.flat_map { |name, text| Agent::Identifiers.ibans(text).map { |_, compact| [ name, compact ] } }

    expect(found.reject { |_, iban| KNOWN_TEST_IBANS.include?(iban) }).to be_empty
  end

  it "has no national number that checks out" do
    found = texts.flat_map { |name, text| text.scan(Agent::Identifiers::NATIONAL_NUMBER).select { |raw| Agent::Identifiers.national_number?(raw) }.map { |raw| [ name, raw ] } }

    expect(found).to be_empty
  end

  it "has no Belgian company or VAT number that checks out" do
    found = texts.flat_map do |name, text|
      (text.scan(Agent::Identifiers::BELGIAN_VAT) + text.scan(Agent::Identifiers::COMPANY_NUMBER)).select { |raw| Agent::Identifiers.belgian_company_number?(raw) }.map { |raw| [ name, raw ] }
    end

    expect(found).to be_empty
  end

  it "has no bank card number" do
    found = texts.flat_map { |name, text| text.scan(Agent::Identifiers::CARD).select { |raw| Agent::Identifiers.card?(raw) }.map { |raw| [ name, raw ] } }

    expect(found).to be_empty
  end

  it "has no e-mail address outside the domains made for tests" do
    found = texts.flat_map { |name, text| text.scan(/[\w.+-]+@([\w-]+\.[\w.-]+)/).flatten.map { |domain| [ name, domain.downcase ] } }

    expect(found.reject { |_, domain| ALLOWED_EMAIL_DOMAINS.any? { |allowed| domain.end_with?(allowed) } }).to be_empty
  end

  it "catches a real-looking identifier when one is put in (the check itself works)" do
    vat = "BE0#{format('%07d', 1_234_567)}#{format('%02d', 97 - 1_234_567 % 97)}"

    expect(Agent::Identifiers.belgian_company_number?(vat)).to be true
    expect(Agent::Identifiers.ibans("pay DE89370400440532013000").size).to eq(1)
    expect(Agent::Identifiers.card?("4111 1111 1111 1111")).to be true
  end
end
