require 'rails_helper'

# An entity under the VAT franchise charges no VAT and treats every document as domestic. Documents already posted are
# left as they are; the rules act on drafts, whenever they are saved or posted.
RSpec.describe Accounting::Invoice, 'under the VAT franchise', type: :model do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal)     { create(:journal, :sale) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:partner) { create(:partner, vat_number: 'BE0123456789') }

  def draft(type: :customer, **attrs)
    journal = type == :customer ? sale_journal : purchase_journal
    inv = create(:invoice, invoice_type: type, partner: partner, fiscal_year: fiscal_year, journal: journal, **attrs)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: '1000.00', vat_rate: '21.00', position: 1)
    inv.reload
  end

  context 'when the entity is in franchise' do
    before { entity.update!(vat_regime: :franchise) }

    it 'charges no VAT on the lines of a customer invoice, whatever rate was typed' do
      inv = draft
      inv.lines.each(&:save!)
      inv.save!

      expect(inv.lines.reload.map(&:vat_rate)).to all(eq(0))
      expect(inv.lines.first.vat_amount).to eq(0)
    end

    it 'has a customer invoice total equal to its total excluding VAT once posted' do
      result = Accounting::PostInvoice.call(invoice: draft)

      expect(result).to be_success
      expect(result.invoice).to have_attributes(subtotal_excl_vat: 1000, vat_amount: 0, total_incl_vat: 1000)
      expect(result.invoice.journal_entry.lines.map(&:account)).not_to include(account_451)
    end

    it 'keeps the VAT rates of a supplier invoice: the supplier did charge it' do
      result = Accounting::PostInvoice.call(invoice: draft(type: :supplier))

      expect(result.invoice).to have_attributes(vat_amount: 210, total_incl_vat: 1210)
    end

    %i[intracom_goods intracom_services construction_reverse_charge export exempt].each do |treatment|
      it "makes #{treatment} domestic, for a customer or a supplier invoice" do
        %i[customer supplier].each do |type|
          inv = draft(type: type, vat_treatment: :domestic)
          inv.vat_treatment = treatment
          inv.valid?
          expect(inv.vat_treatment).to eq('domestic')
        end
      end
    end

    it 'posts a draft made before the switch with no VAT' do
      entity.update!(vat_regime: :normal)
      old = draft
      entity.update!(vat_regime: :franchise)

      result = Accounting::PostInvoice.call(invoice: old)
      expect(result.invoice).to have_attributes(vat_amount: 0, total_incl_vat: 1000)
    end

    it 'leaves a posted invoice untouched when it is saved again' do
      entity.update!(vat_regime: :normal)
      posted = Accounting::PostInvoice.call(invoice: draft).invoice
      entity.update!(vat_regime: :franchise)
      posted.update!(notes: 'checked')

      expect(posted.reload).to have_attributes(vat_amount: 210, total_incl_vat: 1210)
    end
  end

  it 'leaves the VAT of a normal entity alone' do
    result = Accounting::PostInvoice.call(invoice: draft)
    expect(result.invoice).to have_attributes(vat_amount: 210, total_incl_vat: 1210)
  end
end
