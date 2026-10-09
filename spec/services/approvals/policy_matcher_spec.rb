require "rails_helper"

# B01a §4: the first active policy that matches, by priority, applies. Cases are written as a table.
RSpec.describe Approvals::PolicyMatcher do
  include_context "with entity"

  let(:account)  { create(:account) }
  let(:partner)  { create(:partner) }
  let(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:invoice)  { build_invoice(unit_price: "1000.00") } # 1,210.00 incl. VAT

  def build_invoice(unit_price:, partner: self.partner, account: self.account, **attrs)
    create(:invoice, :supplier, partner: partner, fiscal_year: fiscal_year, **attrs).tap do |i|
      create(:invoice_line, invoice: i, account: account, quantity: 1, unit_price: unit_price, vat_rate: "21.00")
    end
  end

  def policy(name, priority:, conditions: {}, subject: :purchase_invoice, active: true)
    Approvals::Policy.create!(name: name, subject: subject, priority: priority, conditions: conditions, active: active)
  end

  it "finds nothing when there is no policy" do
    expect(described_class.call(invoice)).to be_nil
  end

  it "takes the policy of lowest priority number when several match" do
    policy("late", priority: 20)
    first = policy("early", priority: 10)

    expect(described_class.call(invoice)).to eq(first)
  end

  it "ignores a policy that is off, or about something else" do
    policy("off", priority: 1, active: false)
    policy("batches", priority: 2, subject: :payment_batch)
    on = policy("on", priority: 3)

    expect(described_class.call(invoice)).to eq(on)
  end

  describe "amount incl. VAT, in EUR" do
    {
      "below the minimum"        => [ { "min_amount" => "1210.01" }, false ],
      "at the minimum"           => [ { "min_amount" => "1210.00" }, true ],
      "above the maximum"        => [ { "max_amount" => "1209.99" }, false ],
      "at the maximum"           => [ { "max_amount" => "1210.00" }, true ],
      "inside the range"         => [ { "min_amount" => "1000", "max_amount" => "2000" }, true ],
      "outside the range"        => [ { "min_amount" => "2000", "max_amount" => "3000" }, false ]
    }.each do |label, (conditions, matches)|
      it "#{matches ? 'matches' : 'does not match'} #{label}" do
        found = policy("p", priority: 1, conditions: conditions)

        expect(described_class.call(invoice)).to(matches ? eq(found) : be_nil)
      end
    end

    it "counts a foreign currency invoice at its EUR equivalent" do
      foreign = build_invoice(unit_price: "1000.00", currency: "USD", exchange_rate: "2.0", exchange_rate_reason: "contract rate") # 1,210 USD at 2 USD per EUR = 605 EUR
      under = policy("under 700 EUR", priority: 1, conditions: { "max_amount" => "700" })

      expect(described_class.call(foreign)).to eq(under)
    end
  end

  describe "who, what and where" do
    it "matches a listed supplier only" do
      found = policy("this one", priority: 1, conditions: { "partner_ids" => [ partner.id ] })

      expect(described_class.call(invoice)).to eq(found)
      expect(described_class.call(build_invoice(unit_price: "10.00", partner: create(:partner)))).to be_nil
    end

    it "matches a listed expense account on any line" do
      found = policy("this account", priority: 1, conditions: { "account_ids" => [ account.id ] })

      expect(described_class.call(invoice)).to eq(found)
      expect(described_class.call(build_invoice(unit_price: "10.00", account: create(:account)))).to be_nil
    end

    it "matches a listed project" do
      found = policy("project 7", priority: 1, conditions: { "project_ids" => [ 7 ] })

      expect(described_class.call(build_invoice(unit_price: "10.00", project_id: 7))).to eq(found)
      expect(described_class.call(invoice)).to be_nil
    end

    it "matches a listed currency" do
      found = policy("USD", priority: 1, conditions: { "currencies" => [ "USD" ] })
      foreign = build_invoice(unit_price: "10.00", currency: "USD", exchange_rate: "1.1", exchange_rate_reason: "rate")

      expect(described_class.call(foreign)).to eq(found)
      expect(described_class.call(invoice)).to be_nil
    end

    it "matches credit notes only when asked to" do
      found = policy("credit notes", priority: 1, conditions: { "document_types" => [ "credit_note" ] })
      credit_note = build_invoice(unit_price: "10.00", document_type: :credit_note)

      expect(described_class.call(credit_note)).to eq(found)
      expect(described_class.call(invoice)).to be_nil
    end
  end

  describe "first payment to a supplier" do
    let!(:found) { policy("first payment", priority: 1, conditions: { "first_payment" => true }) }

    it "matches a supplier that was never paid" do
      expect(described_class.call(invoice)).to eq(found)
    end

    it "does not match once the supplier has been paid" do
      build_invoice(unit_price: "10.00", status: :paid)

      expect(described_class.call(invoice)).to be_nil
    end

    it "is not fooled by an invoice paid to someone else" do
      build_invoice(unit_price: "10.00", status: :paid, partner: create(:partner))

      expect(described_class.call(invoice)).to eq(found)
    end
  end

  it "needs every condition of a policy to hold" do
    policy("big and from them", priority: 1, conditions: { "min_amount" => "5000", "partner_ids" => [ partner.id ] })

    expect(described_class.call(invoice)).to be_nil
  end

  it "never leaks a policy of another entity" do
    ActsAsTenant.with_tenant(create(:entity)) { Approvals::Policy.create!(name: "elsewhere", subject: :purchase_invoice, priority: 1) }

    expect(described_class.call(invoice)).to be_nil
  end
end
