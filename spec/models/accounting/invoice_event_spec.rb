require 'rails_helper'

# Payment events of API-managed invoices, read by third-party applications (docs/dev/api/inbound-api.md):
# recorded from the Invoice status transitions, whatever service causes them.
RSpec.describe Accounting::InvoiceEvent, type: :model do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'
  let(:entity) { create(:entity, budgetflow_enabled: true) }

  let!(:purchase) { create(:journal, :purchase, default_account: account_440) }
  let!(:cash)     { create(:journal, :cash) }
  let!(:supplier) { create(:partner, :supplier, external_ref: 'BF-P-1') }
  let(:invoice) do
    Accounting::ExternalInvoice.upsert(
      external_ref: 'BF-I-1', partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s,
      lines: [ { account_code: '604000', description: 'Consulting', quantity: '2', unit_price: '50.00', vat_rate: '21' } ]
    ).invoice
  end
  let(:trade_line) { invoice.journal_entry.lines.find_by(account: account_440) }

  # A payment line on the payable account, dated `on`.
  def payment_line(amount, on: Date.current)
    entry = create(:journal_entry, status: :posted, journal: cash, fiscal_year: fiscal_year, entry_date: on, reference: "PAY-#{SecureRandom.hex(3)}")
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: BigDecimal(amount.to_s), credit: 0)
  end

  def events = described_class.where(invoice_id: invoice.id).order(:id)

  it 'records nothing while the invoice is only posted' do
    expect(events).to be_empty
  end

  it 'records a paid event carrying the payment date and the settled amount when the payable line is lettered' do
    paid_on = 3.days.ago.to_date
    Accounting::LetterLines.call(lines: [ trade_line, payment_line(121, on: paid_on) ])

    expect(events.map(&:event_type)).to eq(%w[paid])
    event = events.first
    expect(event).to have_attributes(entity_id: entity.id, invoice_id: invoice.id)
    expect(event.payload).to include('external_ref' => 'BF-I-1', 'revision' => 1, 'invoice_number' => invoice.invoice_number,
                                     'currency' => 'EUR', 'amount_eur' => '121.0', 'paid_on' => paid_on.iso8601)
    expect(event.occurred_at).to be_within(5.seconds).of(Time.current)
  end

  it 'records partially_paid with what is settled so far, then paid' do
    Accounting::AllocateLines.call(lines: [ trade_line, payment_line(60) ])
    Accounting::AllocateLines.call(lines: [ trade_line.reload, payment_line(61) ])

    expect(events.map(&:event_type)).to eq(%w[partially_paid paid])
    expect(events.first.payload['amount_eur']).to eq('60.0')
    expect(events.last.payload['amount_eur']).to eq('121.0')
  end

  it 'records payment_reopened when the payment is undone' do
    invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
    invoice.reload.reopen!

    expect(events.map(&:event_type)).to eq(%w[payment_reopened])
  end

  it 'falls back to the transition date and the invoice total when there is no lettering yet (SEPA batch executed)' do
    invoice.pay!

    expect(events.first.payload).to include('amount_eur' => '121.0', 'paid_on' => Date.current.iso8601)
  end

  it 'ignores invoices typed in the UI and cancellations' do
    typed = create(:invoice, :draft, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year)
    typed.update_columns(status: Accounting::Invoice.statuses[:posted])
    typed.reload.pay!
    invoice.reload.cancel!

    expect(described_class.where(invoice_id: [ typed.id, invoice.id ])).to be_empty
  end

  describe 'lifecycle events' do
    let(:draft) do
      Accounting::ExternalInvoice.upsert(
        external_ref: 'BF-I-2', partner_external_ref: 'BF-P-1', invoice_type: 'supplier', invoice_date: Date.current.to_s, post: false,
        lines: [ { account_code: '604000', description: 'X', quantity: '1', unit_price: '100', vat_rate: '21' } ]
      ).invoice
    end

    it 'records posted, with the number, when the accountant posts an API draft' do
      expect { Accounting::PostInvoice.call(invoice: draft) }
        .to change { described_class.where(invoice_id: draft.id, event_type: 'posted').count }.by(1)

      expect(described_class.where(invoice_id: draft.id).last.payload).to include('external_ref' => 'BF-I-2', 'invoice_number' => draft.reload.invoice_number)
    end

    it 'records a returned event carrying the reason' do
      described_class.record!(draft, 'returned', reason: 'Wrong budget line')

      expect(described_class.where(invoice_id: draft.id).last.payload).to include('reason' => 'Wrong budget line', 'external_ref' => 'BF-I-2')
    end
  end

  describe 'the bank confirmation of a payment already made (SEPA batch)' do
    let(:bank_account) { create(:bank_account) }
    let(:batch) do
      b = create(:payment_batch, :generated, bank_account: bank_account, requested_execution_date: 1.day.from_now.to_date, total_amount: BigDecimal('121'))
      create(:payment_batch_line, payment_batch: b, invoice: invoice, amount: invoice.total_incl_vat)
      b.reload
    end
    let(:tx) do
      create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('-121'), transaction_date: Date.current,
                                value_date: 1.day.from_now.to_date, reference: 'BANK-REF-9')
    end

    it 'adds a payment_confirmed event with the value date and the bank reference once the debit is linked to the batch' do
      Payments::ExecutePaymentBatch.call(payment_batch: batch)
      expect(events.map(&:event_type)).to eq(%w[paid])
      expect(events.first.payload['settlements'].first).to include('source' => 'payment_batch', 'reference' => batch.message_id)

      Accounting::LinkTransactionToSettlement.call(transaction: tx, payment_batch: batch)

      expect(events.map(&:event_type)).to eq(%w[paid payment_confirmed])
      confirmed = events.last.payload
      expect(confirmed).to include('paid_on' => 1.day.from_now.to_date.iso8601, 'reference' => 'BANK-REF-9', 'amount_eur' => '121.0')
      expect(confirmed['settlements'].first).to include('source' => 'bank_transaction', 'value_date' => 1.day.from_now.to_date.iso8601)
    end

    it 'says nothing new when the third party already knows the bank facts' do
      Accounting::LinkTransactionToSettlement.call(transaction: tx, payment_batch: batch) # executes the batch and links in one go

      expect(events.map(&:event_type)).to eq(%w[paid])
      expect(events.first.payload['reference']).to eq('BANK-REF-9')
    end

    it 'does nothing for an entity that does not use BudgetFlow' do
      Payments::ExecutePaymentBatch.call(payment_batch: batch)
      entity.update_columns(budgetflow_enabled: false)

      expect { Accounting::LinkTransactionToSettlement.call(transaction: tx, payment_batch: batch) }
        .not_to change(described_class, :count)
    end
  end
end
