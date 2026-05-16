require "rails_helper"

RSpec.describe Accounting::Actions::ValidateNoOpenEntries do
  include_context "with_open_fiscal_year"

  let(:journal) { create(:journal, :purchase) }

  describe ".execute" do
    context "aucune écriture brouillon" do
      it "ne fail pas le contexte" do
        ctx = LightService::Context.make(fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx).to be_success
      end
    end

    context "avec des écritures brouillon" do
      before do
        create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
               entry_date: fiscal_year.start_date + 1)
      end

      it "fail le contexte" do
        ctx = LightService::Context.make(fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx).to be_failure
      end

      it "inclut le nombre d'écritures ouvertes dans le message d'erreur" do
        ctx = LightService::Context.make(fiscal_year: fiscal_year)
        described_class.execute(ctx)
        expect(ctx.message).to include("1")
      end
    end
  end
end
