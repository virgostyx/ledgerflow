require 'rails_helper'

RSpec.describe 'Opening balances import screen', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  before do
    create(:journal, journal_type: :misc, code: 'OD', sequence_prefix: 'OD')
    create(:account, code: '400000', account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true)
    create(:account, code: '440000', account_class: 4, account_type: :liability, normal_balance: :credit, reconcilable: true)
    create(:account, code: '499000', account_class: 4, account_type: :asset, normal_balance: :debit)
    create(:account, code: '100000', account_class: 1, account_type: :equity, normal_balance: :credit)
    login_as accountant, scope: :user
  end

  def csv(name, content)
    Rails.root.join('tmp', name).tap { |path| File.write(path, content) }.to_s
  end

  it 'checks first, keeps the chosen files, then imports' do
    balances = csv('opening_balances_system.csv', "account_code,debit,credit\n400000,300,0\n100000,0,300\n")
    invoices = csv('opening_invoices_system.csv',
                   "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\ncustomer,Acme SA,,A1,2025-11-15,2025-12-15,300\n")

    visit accounting_settings_opening_balance_path
    attach_file 'balances_file', balances
    attach_file 'invoices_file', invoices
    click_button 'Check only'

    expect(page).to have_content('Check passed')
    expect(Accounting::Invoice.count).to eq(0)
    expect(find_field('balances_file').value).to be_present # the frame reloaded, not the page

    click_button 'Import'
    click_button 'Confirm' # the app's own confirmation modal
    expect(page).to have_content('Import complete')
    expect(Accounting::Invoice.find_by!(invoice_number: 'A1')).to be_posted
  ensure
    FileUtils.rm_f([ balances, invoices ].compact)
  end
end
