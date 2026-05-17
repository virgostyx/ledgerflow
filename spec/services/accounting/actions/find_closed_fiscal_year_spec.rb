require "rails_helper"

RSpec.describe Accounting::Actions::FindClosedFiscalYear do
  include_context "with_open_fiscal_year"

  describe ".execute" do
    context "when a closed fiscal year precedes the new one" do
      let!(:prev_year) do
        create(:fiscal_year, year: fiscal_year.year - 1,
               start_date: fiscal_year.start_date - 1.year,
               end_date: fiscal_year.start_date - 1.day,
               status: :closed)
      end

      it "sets previous_fiscal_year in context" do
        ctx = LightService::Context.make(new_fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx[:previous_fiscal_year]).to eq(prev_year)
      end

      it "does not fail the context" do
        ctx = LightService::Context.make(new_fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx).to be_success
      end
    end

    context "when no closed fiscal year exists" do
      it "sets previous_fiscal_year to nil" do
        ctx = LightService::Context.make(new_fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx[:previous_fiscal_year]).to be_nil
      end

      it "does not fail the context" do
        ctx = LightService::Context.make(new_fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx).to be_success
      end
    end

    context "when only a non-closed fiscal year exists" do
      let!(:other_open) do
        create(:fiscal_year, year: fiscal_year.year - 1,
               start_date: fiscal_year.start_date - 1.year,
               end_date: fiscal_year.start_date - 1.day,
               status: :pre_closing)
      end

      it "ignores non-closed years and sets previous_fiscal_year to nil" do
        ctx = LightService::Context.make(new_fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx[:previous_fiscal_year]).to be_nil
      end
    end
  end
end
