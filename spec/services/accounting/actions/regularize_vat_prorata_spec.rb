require 'rails_helper'

RSpec.describe Accounting::Actions::RegularizeVatProrata, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:misc_journal) { create(:journal, journal_type: :misc) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:partner) { create(:partner) }

  def post_purchase_invoice(unit_price:, vat_rate: '21.00')
    inv = create(:invoice, invoice_type: :supplier, partner: partner, fiscal_year: fiscal_year, journal: purchase_journal)
    create(:invoice_line, invoice: inv, account: account_604, quantity: 1, unit_price: unit_price, vat_rate: vat_rate, position: 1)
    inv.compute_totals
    inv.save!
    Accounting::PostInvoice.call(invoice: inv)
  end

  describe '.call' do
    context "l entité n avait pas de prorata pendant l année (tout déduit à 100%)" do
      before { post_purchase_invoice(unit_price: '1000.00') } # 210.00 VAT, fully deducted

      it "ne crée aucune écriture si le prorata final correspond au réel (100%)" do
        result = described_class.call(fiscal_year_id: fiscal_year.id, final_prorata_rate: BigDecimal('100'))
        expect(result).to be_success
        expect(result[:journal_entry]).to be_nil
      end

      it "régularise en défaveur de l entité si le prorata final est plus bas (70%)" do
        result = described_class.call(fiscal_year_id: fiscal_year.id, final_prorata_rate: BigDecimal('70'))
        expect(result).to be_success
        entry = result[:journal_entry]
        expect(entry).to be_posted

        deductible_line = entry.lines.find { |l| l.account == account_411 }
        expect(deductible_line.credit).to eq(BigDecimal('63.00')) # 210 - 70% * 210 = 63 reversed
        expect(deductible_line.vat_code).to eq(61)
      end
    end

    context "un avoir fournisseur reçu pendant l année (prorata 70%, final 100%)" do
      before do
        entity.update!(vat_prorata_rate: '70.00')
        post_purchase_invoice(unit_price: '1000.00') # 210 VAT: 147 deducted, 63 non-deductible
        credit = create(:invoice, invoice_type: :supplier, partner: partner, fiscal_year: fiscal_year,
                        journal: purchase_journal, document_type: :credit_note,
                        credited_invoice: Accounting::Invoice.last)
        create(:invoice_line, invoice: credit, account: account_604, quantity: 1, unit_price: '500.00',
               vat_rate: '21.00', position: 1)
        credit.compute_totals
        credit.save!
        Accounting::PostInvoice.call(invoice: credit) # VAT 105: 73.50 reversed (63), 31.50 non-deductible
      end

      it "part du net déduit (147 - 73,50) et du net non déductible (63 - 31,50)" do
        result = described_class.call(fiscal_year_id: fiscal_year.id, final_prorata_rate: BigDecimal('100'))
        deductible_line = result[:journal_entry].lines.find { |l| l.account == account_411 }
        expect(deductible_line.debit).to eq(BigDecimal('31.50')) # 105 * 100% - 73.50
      end
    end

    context "l entité avait un prorata de 70% pendant l année, prorata final de 80%" do
      before do
        entity.update!(vat_prorata_rate: '70.00')
        post_purchase_invoice(unit_price: '1000.00') # 210 VAT, 147 deducted, 63 non-deductible
      end

      it "récupère la différence (168 théorique - 147 déjà déduit = 21)" do
        result = described_class.call(fiscal_year_id: fiscal_year.id, final_prorata_rate: BigDecimal('80'))
        expect(result).to be_success
        entry = result[:journal_entry]

        deductible_line = entry.lines.find { |l| l.account == account_411 }
        expect(deductible_line.debit).to eq(BigDecimal('21.00'))
        expect(deductible_line.vat_code).to eq(62)

        non_deductible_line = entry.lines.find { |l| l.account == account_640400 }
        expect(non_deductible_line.credit).to eq(BigDecimal('21.00'))
      end

      it "l écriture de régularisation est équilibrée" do
        result = described_class.call(fiscal_year_id: fiscal_year.id, final_prorata_rate: BigDecimal('80'))
        entry = result[:journal_entry]
        expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
      end
    end
  end
end
