require 'rails_helper'

RSpec.describe 'Invoice form dates', type: :system, js: true do
  include_context 'with_open_fiscal_year'

  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:net30)      { create(:partner, name: 'Net 30 SA', payment_terms_days: 30) }
  let!(:net45)      { create(:partner, name: 'Net 45 SA', payment_terms_days: 45) }
  let!(:on_receipt) { create(:partner, name: 'Cash Co', payment_terms_days: 0) }

  before { login_as accountant, scope: :user }

  def invoice_date = find('#accounting_invoice_invoice_date').value
  def due_date     = find('#accounting_invoice_due_date').value
  def pick_partner(name) = select(name, from: 'accounting_invoice_partner_id')

  describe 'a new invoice' do
    before { visit accounting_new_sales_path }

    it 'starts on today, with no due date until a partner is chosen' do
      expect(invoice_date).to eq(Date.current.iso8601)
      expect(due_date).to eq('')
    end

    it 'sets the due date to the invoice date plus the payment terms of the partner' do
      pick_partner('Net 45 SA')
      expect(due_date).to eq((Date.current + 45).iso8601)
    end

    it 'follows a change of partner' do
      pick_partner('Net 45 SA')
      pick_partner('Cash Co')
      expect(due_date).to eq(Date.current.iso8601)

      pick_partner('Net 30 SA')
      expect(due_date).to eq((Date.current + 30).iso8601)
    end

    it 'follows a change of the invoice date' do
      pick_partner('Net 45 SA')
      find('#accounting_invoice_invoice_date').set(Date.new(2030, 1, 10))

      expect(due_date).to eq('2030-02-24')
    end

    it 'sets the due date when the invoice date is changed before the partner is chosen' do
      find('#accounting_invoice_invoice_date').set(Date.new(2030, 1, 10))
      pick_partner('Net 30 SA')

      expect(due_date).to eq('2030-02-09')
    end

    it 'keeps a due date typed by hand when the partner or the invoice date changes' do
      pick_partner('Net 45 SA')
      find('#accounting_invoice_due_date').set(Date.new(2031, 5, 15))

      pick_partner('Cash Co')
      find('#accounting_invoice_invoice_date').set(Date.new(2030, 1, 10))

      expect(due_date).to eq('2031-05-15')
    end
  end

  describe 'editing a saved draft' do
    let!(:draft) do
      create(:invoice, invoice_type: :customer, partner: net30, fiscal_year: fiscal_year, invoice_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 3, 15))
    end

    it 'never overwrites its due date when the partner changes' do
      visit edit_accounting_invoice_path(draft)
      pick_partner('Net 45 SA')

      expect(due_date).to eq('2026-03-15')
    end
  end
end
