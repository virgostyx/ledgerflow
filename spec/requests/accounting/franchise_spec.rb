require 'rails_helper'

RSpec.describe 'The VAT franchise in the interface', type: :request do
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { sign_in accountant }

  def page = Nokogiri::HTML(response.body)
  def options_of(selector) = page.css("#{selector} option").map { |o| o['value'] }.uniq # the form has a row and a template of it

  context 'for an entity in franchise' do
    before { entity.update!(vat_regime: :franchise) }

    it 'offers only 0% on the lines of a sale' do
      get accounting_new_sales_path
      expect(options_of("select[data-line-vat-rate]")).to eq([ '0.00' ])
      expect(response.body).to include('data-line-vat-rate="true"')
      expect(response.body).not_to include('<option value="21.00"')
    end

    it 'keeps every rate on the lines of a purchase: the supplier charged its VAT' do
      get accounting_new_purchases_path
      expect(response.body).to include('<option value="21.00"')
    end

    it 'offers only the domestic treatment, on a sale and on a purchase' do
      [ accounting_new_sales_path, accounting_new_purchases_path ].each do |path|
        get path
        expect(options_of('select#accounting_invoice_vat_treatment')).to eq([ 'domestic' ])
      end
    end

    it 'says that no VAT is charged, without the explanation of the normal regime that would contradict it' do
      get accounting_new_sales_path
      expect(response.body).to include('VAT franchise: no VAT is charged')
      expect(response.body).not_to include('Belgian VAT applies')

      get accounting_new_purchases_path
      expect(response.body).to include('cannot be recovered')
      expect(response.body).not_to include('Belgian VAT applies')
    end

    it 'hides the VAT declarations, the intracom listing and the year-end VAT regularization' do
      get accounting_root_path
      expect(response.body).not_to include('VAT Declarations')
      expect(response.body).not_to include('Intracommunity Listings')

      entity.update!(vat_scheme: :mixed)
      get accounting_fiscal_year_path(fiscal_year)
      expect(response.body).not_to include(I18n.t('accounting.fiscal_years.vat_regularization.title'))
    end
  end

  context 'for an entity with the normal VAT regime' do
    it 'offers all rates, all treatments and the VAT screens' do
      get accounting_new_sales_path
      expect(options_of("select[data-line-vat-rate]")).to eq(%w[0.00 6.00 12.00 21.00])
      expect(options_of('select#accounting_invoice_vat_treatment').size).to eq(Accounting::Invoice.vat_treatments.size)

      get accounting_root_path
      expect(response.body).to include('VAT Declarations', 'Intracommunity Listings')
    end
  end
end
