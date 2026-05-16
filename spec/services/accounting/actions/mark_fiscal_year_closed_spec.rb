require "rails_helper"

RSpec.describe Accounting::Actions::MarkFiscalYearClosed do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user, role: :accountant) }

  describe ".execute" do
    it "marque l'exercice comme clôturé" do
      ctx = LightService::Context.make(fiscal_year: fiscal_year, closed_by: user)
      described_class.execute(ctx)
      expect(fiscal_year.reload.status).to eq("closed")
    end

    it "enregistre closed_at" do
      travel_to Time.zone.local(2025, 12, 31, 23, 59) do
        ctx = LightService::Context.make(fiscal_year: fiscal_year, closed_by: user)
        described_class.execute(ctx)
        expect(fiscal_year.reload.closed_at).to be_within(1.second).of(Time.current)
      end
    end

    it "enregistre closed_by_id" do
      ctx = LightService::Context.make(fiscal_year: fiscal_year, closed_by: user)
      described_class.execute(ctx)
      expect(fiscal_year.reload.closed_by_id).to eq(user.id)
    end

    it "ne fail pas le contexte" do
      ctx = LightService::Context.make(fiscal_year: fiscal_year, closed_by: user)
      described_class.execute(ctx)
      expect(ctx).to be_success
    end
  end
end
