require 'rails_helper'

RSpec.describe 'Accounting::BankReconciliation — pay a supplier invoice', type: :request do
  include_context 'with_pcmn_accounts'
  include_context 'with_open_fiscal_year'

  let(:accountant) { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:purchase)  { create(:journal, :purchase, default_account: account_440) }
  let!(:misc)      { create(:journal, journal_type: :misc, code: 'OD', label_fr: 'Miscellaneous') }
  let!(:supplier)  { create(:partner, :supplier, :with_iban, external_ref: 'S1') }
  let(:bank_account) { create(:bank_account) }
  let(:invoice) do
    Accounting::ExternalInvoice.upsert(
      external_ref: 'INV-1', partner_external_ref: 'S1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      lines: [ { account_code: '604000', description: 'Work', quantity: '1', unit_price: '100', vat_rate: '0' } ]
    ).invoice
  end
  let(:tx) { create(:bank_transaction, bank_account: bank_account, amount: -100, reference: 'PAY-1') }

  before { sign_in accountant }

  def pay
    patch accounting_bank_reconciliation_path, params: {
      bank_reconciliation: { bank_transaction_id: tx.id, pay_invoice_id: invoice.id }
    }
  end

  it 'settles the invoice from the pending debit' do
    pay

    expect(flash[:alert]).to be_nil
    expect(tx.reload).to be_reconciled
    expect(invoice.reload).to be_paid
  end

  it 'alerts when the service refuses (EUR amount missing on a foreign account)' do
    tx.update_columns(currency: 'USD')
    bank_account.update_columns(currency: 'USD')

    pay

    expect(flash[:alert]).to be_present
    expect(tx.reload).to be_pending
  end
end
