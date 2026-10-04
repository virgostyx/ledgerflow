require "rails_helper"

# F11: the rules of the entity for exchange rates, a fixed currency on an account, a default currency on a partner.
RSpec.describe "Multi-currency settings", type: :model do
  include_context "with entity"

  describe Entity do
    it "defaults to the daily rate of the date of the document, a 5 % alert, no fallback, realized differences posted, the unrealized loss booked and the unrealized gain not" do
      expect(entity).to have_attributes(rate_policy: "daily", rate_date_basis: "document_date", rate_alert_pct: BigDecimal("5"), rate_fallback_currencies: [],
                                        fx_realized_as_draft: false, fx_unrealized_loss: "expense", fx_unrealized_gain: "ignore",
                                        fx_loss_account_code: "651200", fx_gain_account_code: "751100")
    end

    it "offers the daily rate, the monthly average and a manual rate; the date of the document or the accounting date" do
      expect(described_class.rate_policies.keys).to eq(%w[daily monthly_average manual])
      expect(described_class.rate_date_bases.keys).to eq(%w[document_date accounting_date])
    end

    it "treats an unrealized loss by expensing it or leaving it, and a gain by deferring, recognizing or leaving it" do
      expect(described_class.fx_unrealized_losses.keys).to eq(%w[expense ignore])
      expect(described_class.fx_unrealized_gains.keys).to eq(%w[defer recognize ignore])
    end

    it "refuses a negative alert, and a fallback currency that is not one" do
      entity.rate_alert_pct = -1
      expect(entity).not_to be_valid
      entity.rate_alert_pct = 5
      entity.rate_fallback_currencies = [ "usd" ]
      expect(entity).not_to be_valid
      entity.rate_fallback_currencies = [ "USD", "ZMW" ]
      expect(entity).to be_valid
    end

    it "needs the two exchange difference accounts" do
      entity.fx_loss_account_code = ""
      expect(entity).not_to be_valid
    end
  end

  describe Accounting::Account do
    it "can be kept in a fixed currency, which can be revalued at closing" do
      account = build(:account, currency: "USD", revalue_at_closing: true)
      expect(account).to be_valid
    end

    it "refuses a currency that is not supported, and a revaluation without a currency" do
      expect(build(:account, currency: "XXX")).not_to be_valid
      expect(build(:account, currency: nil, revalue_at_closing: true)).not_to be_valid
    end
  end

  describe Accounting::Partner do
    it "has EUR as its currency unless set, and refuses one that is not supported" do
      expect(build(:partner).currency).to eq("EUR")
      expect(build(:partner, currency: "USD")).to be_valid
      expect(build(:partner, currency: "ZZZ")).not_to be_valid
    end
  end
end
