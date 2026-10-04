require "rails_helper"

RSpec.describe Accounting::DunningTexts do
  include_context "with entity"

  let(:policy) { Accounting::DunningPolicy.for(ActsAsTenant.current_tenant) }
  let(:vars) do
    { partner_name: "Alice SRL", entity_name: "Acme ASBL", total: "150,50 €", oldest_days: "30", date: "04/10/2026", invoice_list: "- 2026/001 : 150,50 €",
      charges: "", grand_total: "150,50 €", signature: "The team" }
  end

  it "has a built-in text for each of the three levels in French, Dutch and English" do
    Accounting::DunningPolicy::LEVELS.product(%w[fr nl en]).each do |level, language|
      text = described_class.render(policy: policy, level: level, language: language, variables: vars)
      expect(text[:subject]).to be_present
      expect(text[:body]).to include("Alice SRL", "150,50 €", "- 2026/001", "The team")
      expect(text[:body]).not_to include("{{")
    end
  end

  it "falls back to English for a language it does not have" do
    expect(described_class.render(policy: policy, level: 1, language: "de", variables: vars)).to eq(described_class.render(policy: policy, level: 1, language: "en", variables: vars))
  end

  it "uses the text the entity wrote in place of the built-in one, for that level and language only" do
    policy.update!(templates: { "2" => { "fr" => { "subject" => "Rappel de {{partner_name}}", "body" => "Bonjour, {{total}}" } } })
    expect(described_class.render(policy: policy, level: 2, language: "fr", variables: vars)).to eq(subject: "Rappel de Alice SRL", body: "Bonjour, 150,50 €")
    expect(described_class.render(policy: policy, level: 1, language: "fr", variables: vars)[:subject]).not_to eq("Rappel de Alice SRL")
  end

  it "refuses a text with a variable it does not know, or a level or language outside the three" do
    policy.templates = { "1" => { "fr" => { "subject" => "x", "body" => "Voir {{secret}}" } } }
    expect(policy).not_to be_valid
    policy.templates = { "4" => { "fr" => { "subject" => "x", "body" => "y" } } }
    expect(policy).not_to be_valid
  end

  it "carries the charges where there are some" do
    body = described_class.render(policy: policy, level: 1, language: "en", variables: vars.merge(charges: "Late interest: 2,00 €"))[:body]
    expect(body).to include("Late interest: 2,00 €")
  end
end
