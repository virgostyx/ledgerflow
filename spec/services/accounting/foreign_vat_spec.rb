require 'rails_helper'

# A purchase from a supplier abroad whose invoice carries that country's VAT (16 % in Zambia): not Belgian VAT, so nothing to deduct and nothing in the
# Belgian VAT return. The VAT is a cost: it goes into the expense of the line (so the analytical accounts, and the budget lines, carry it) and the
# supplier is owed the whole.
RSpec.describe 'Foreign VAT, booked as a cost' do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase, default_account: account_440) }
  let(:invoice) do
    create(:invoice, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, vat_treatment: :foreign_vat).tap do |i|
      create(:invoice_line, invoice: i, account: account_604, quantity: 1, unit_price: '1000.00', vat_rate: '16.00', description: 'Services')
      i.reload.compute_totals
      i.save!
    end
  end

  it 'is a treatment of its own' do
    expect(Accounting::Invoice.vat_treatments).to include('foreign_vat' => 6)
  end

  it 'is owed whole to the supplier, VAT included, and keeps the VAT amount for the record' do
    expect(invoice).to have_attributes(subtotal_excl_vat: BigDecimal('1000'), vat_amount: BigDecimal('160'), total_incl_vat: BigDecimal('1160'))
  end

  it 'is only for purchases' do
    sale = build(:invoice, invoice_type: :customer, vat_treatment: :foreign_vat)

    expect(sale).not_to be_valid
    expect(sale.errors[:vat_treatment].join).to include('purchases')
  end

  describe 'when it is posted' do
    before { Accounting::PostInvoice.call(invoice: invoice) }

    let(:lines) { invoice.reload.journal_entry.lines.includes(:account).to_a }

    it 'puts the VAT in the expense, with no VAT line' do
      expect(lines.map { |l| [ l.account.code, l.debit, l.credit ] }).to match_array([
        [ account_604.code, BigDecimal('1160'), BigDecimal('0') ],
        [ '440000', BigDecimal('0'), BigDecimal('1160') ]
      ])
    end

    it 'declares nothing in the Belgian VAT return: no grid on any line' do
      expect(lines.map(&:vat_code)).to all(be_nil)
    end

    it 'is balanced' do
      expect(lines.sum(&:debit)).to eq(lines.sum(&:credit))
    end
  end

  describe 'a supplier abroad that charged no VAT (exempted, or below the threshold)' do
    let(:invoice) do
      create(:invoice, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal, vat_treatment: :foreign_vat).tap do |i|
        create(:invoice_line, invoice: i, account: account_604, quantity: 1, unit_price: '1000.00', vat_rate: '0.00', description: 'Services')
        i.reload.compute_totals
        i.save!
      end
    end

    it 'is booked at its amount, in no grid of the Belgian VAT return' do
      Accounting::PostInvoice.call(invoice: invoice)
      lines = invoice.reload.journal_entry.lines.includes(:account).to_a

      expect(lines.map { |l| [ l.account.code, l.debit, l.credit ] }).to match_array([ [ account_604.code, BigDecimal('1000'), BigDecimal('0') ], [ '440000', BigDecimal('0'), BigDecimal('1000') ] ])
      expect(lines.map(&:vat_code)).to all(be_nil)
    end
  end
end
