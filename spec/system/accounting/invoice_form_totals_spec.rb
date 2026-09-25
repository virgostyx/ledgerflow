require 'rails_helper'

RSpec.describe 'Invoice form totals under a non-domestic VAT treatment', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:account_700) { create(:account, code: '700000', label_fr: 'Ventes', is_leaf: true) }
  let!(:sale_journal) { create(:journal, :sale) }

  NON_DOMESTIC = { 'Intracom goods' => 'intracom_goods', 'Intracom services' => 'intracom_services',
                   'Construction reverse charge' => 'construction_reverse_charge', 'Export' => 'export', 'Exempt' => 'exempt' }.freeze

  before { login_as accountant, scope: :user }

  # "1 210,00 €" or "1 210,00 EUR" (server or script rendered) => 1210.0
  def number(css) = find(css).text.gsub(/[^\d,]/, '').tr(',', '.').to_d
  def subtotal = number('[data-invoice-form-target="invoiceSubtotal"]')
  def vat      = number('[data-invoice-form-target="invoiceVat"]')
  def total    = number('[data-invoice-form-target="invoiceTotal"]')
  def line_vat   = number('[data-line-vat-display]')
  def line_total = number('[data-line-total-display]')

  def enter_price(value, index: 0)
    find(%(input[name="accounting_invoice[lines_attributes][#{index}][unit_price]"])).set(value)
  end

  def choose_treatment(label) = select(label, from: 'accounting_invoice_vat_treatment')

  describe 'a new invoice' do
    before { visit accounting_new_sales_path }

    it 'adds 21% VAT to a domestic invoice' do
      enter_price('1000')

      expect([ subtotal, vat, total ]).to eq([ 1000, 210, 1210 ].map(&:to_d))
      expect([ line_vat, line_total ]).to eq([ 210, 1210 ].map(&:to_d))
    end

    NON_DOMESTIC.each do |label, _value|
      it "charges no VAT under #{label}: the total is the amount excl. VAT" do
        enter_price('1000')
        choose_treatment(label)

        expect([ subtotal, vat, total ]).to eq([ 1000, 0, 1000 ].map(&:to_d))
        expect([ line_vat, line_total ]).to eq([ 0, 1000 ].map(&:to_d))
      end
    end

    it 'keeps the total right when the amount is typed after choosing the treatment' do
      choose_treatment('Intracom services')
      enter_price('1000')

      expect([ vat, total ]).to eq([ 0, 1000 ].map(&:to_d))
    end

    it 'comes back to the VAT-inclusive total when switching back to Domestic' do
      enter_price('1000')
      choose_treatment('Export')
      choose_treatment('Domestic')

      expect([ vat, total ]).to eq([ 210, 1210 ].map(&:to_d))
    end

    it 'says why no VAT is charged, only for a non-domestic treatment' do
      expect(page).not_to have_content('VAT is not charged')

      choose_treatment('Intracom services')
      expect(page).to have_content('VAT is not charged')

      choose_treatment('Domestic')
      expect(page).not_to have_content('VAT is not charged')
    end
  end

  describe 'editing a draft' do
    let(:eu_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }

    def draft(vat_treatment)
      inv = create(:invoice, invoice_type: :customer, partner: eu_partner, fiscal_year: fiscal_year, journal: sale_journal,
                   vat_treatment: vat_treatment)
      create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: '1000.00', vat_rate: '21.00', position: 1)
      inv
    end

    it 'shows the right totals on load for a non-domestic draft' do
      visit edit_accounting_invoice_path(draft(:intracom_services))

      expect([ subtotal, vat, total ]).to eq([ 1000, 0, 1000 ].map(&:to_d))
      expect([ line_vat, line_total ]).to eq([ 0, 1000 ].map(&:to_d))
      expect(page).to have_content('VAT is not charged')
    end

    it 'shows the totals on load for a domestic draft, not zeros' do
      visit edit_accounting_invoice_path(draft(:domestic))

      expect([ subtotal, vat, total ]).to eq([ 1000, 210, 1210 ].map(&:to_d))
    end
  end
end
