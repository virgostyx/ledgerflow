require 'rails_helper'

RSpec.describe 'VAT treatment help on the invoice form', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before { login_as accountant, scope: :user }

  def help(treatment, type) = I18n.t("accounting.invoices.vat_treatment_help.#{treatment}.#{type}")
  def choose_treatment(label) = select(label, from: 'accounting_invoice_vat_treatment')

  {
    'Domestic' => 'domestic', 'Intracom goods' => 'intracom_goods', 'Intracom services' => 'intracom_services',
    'Construction reverse charge' => 'construction_reverse_charge', 'Export' => 'export', 'Exempt' => 'exempt'
  }.each do |label, treatment|
    it "shows only the explanation of #{label} on a sale" do
      visit accounting_new_sales_path
      choose_treatment(label)

      expect(page).to have_content(help(treatment, 'customer'))
      (Accounting::Invoice.vat_treatments.keys - [ treatment ]).each do |other|
        expect(page).not_to have_content(help(other, 'customer'))
      end
    end
  end

  it 'uses the supplier wording on a purchase' do
    visit accounting_new_purchases_path
    choose_treatment('Intracom services')

    expect(page).to have_content(help('intracom_services', 'supplier'))
    expect(page).not_to have_content(help('intracom_services', 'customer'))
  end

  it 'starts with the explanation of the default treatment' do
    visit accounting_new_sales_path
    expect(page).to have_content(help('domestic', 'customer'))
  end
end
