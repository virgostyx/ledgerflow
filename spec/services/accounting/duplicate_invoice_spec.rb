require 'rails_helper'

RSpec.describe Accounting::DuplicateInvoice, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:partner) { create(:partner, payment_terms_days: 45) }
  let(:axis) { create(:analytical_axis) }
  let(:analytical_account) { create(:analytical_account, analytical_axis: axis) }

  # A posted invoice dated well in the past, due 30 days later, with two lines (the first one analytically annotated).
  let!(:original) do
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal,
                 invoice_date: Date.new(2025, 1, 10), due_date: Date.new(2025, 2, 9), currency: 'USD', exchange_rate: BigDecimal('0.9'),
                 vat_treatment: :domestic, description: 'Monthly retainer', notes: 'Thanks!', external_ref: 'PO-42')
    line = create(:invoice_line, invoice: inv, account: account_700, description: 'Consulting', quantity: 2, unit_price: '500.00', vat_rate: '21.00', position: 1)
    create(:invoice_line, invoice: inv, account: account_700, description: 'Travel', quantity: 1, unit_price: '80.00', vat_rate: '6.00', position: 2)
    create(:invoice_line_annotation, invoice_line: line, analytical_axis: axis, analytical_account: analytical_account)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  subject(:result) { described_class.call(invoice: original) }
  let(:copy) { result[:invoice] }

  it 'creates a new draft invoice and leaves the original untouched' do
    expect { result }.to change(Accounting::Invoice, :count).by(1)

    expect(result).to be_success
    expect(copy).to be_persisted.and be_draft
    expect(copy.id).not_to eq(original.id)
    expect(original.reload).to be_posted
  end

  it 'copies the partner, type, journal, currency, rate, VAT treatment, description and notes' do
    expect(copy).to have_attributes(partner: partner, invoice_type: 'customer', journal: sale_journal, currency: 'USD',
                                    exchange_rate: BigDecimal('0.9'), vat_treatment: 'domestic', description: 'Monthly retainer',
                                    notes: 'Thanks!', document_type: 'invoice')
  end

  it 'dates it today, in the open fiscal year, keeping the payment interval of the original' do
    expect(copy).to have_attributes(invoice_date: Date.current, due_date: Date.current + 30, fiscal_year: fiscal_year)
  end

  describe 'at a given date' do
    let(:date) { fiscal_year.start_date + 40 }

    it 'dates the copy on that date and moves the due date with it' do
      result = described_class.call(invoice: original, invoice_date: date)

      expect(result).to be_success
      expect(result[:invoice]).to have_attributes(invoice_date: date, due_date: date + 30, fiscal_year: fiscal_year)
    end

    it 'refuses a date outside every open fiscal year, creating nothing' do
      result = nil
      expect { result = described_class.call(invoice: original, invoice_date: fiscal_year.end_date + 400) }
        .not_to change(Accounting::Invoice, :count)

      expect(result).to be_failure
      expect(result.message).to be_present
    end

    it 'refuses a date in a closed fiscal year' do
      fiscal_year.update!(status: :closed, closed_at: Time.current)
      create(:fiscal_year, year: fiscal_year.year + 1, start_date: fiscal_year.end_date + 1, end_date: fiscal_year.end_date + 365, status: :open)

      expect(described_class.call(invoice: original, invoice_date: date)).to be_failure
    end
  end

  it 'does not copy what belongs to the original document' do
    expect(copy).to have_attributes(invoice_number: nil, journal_entry: nil, external_ref: nil, peppol_id: nil,
                                    peppol_status: 'not_sent', credited_invoice: nil, cash_journal: nil)
  end

  it 'copies the lines, in their order' do
    expect(copy.lines.map { |l| [ l.description, l.account, l.quantity, l.unit_price, l.vat_rate, l.position ] })
      .to eq([ [ 'Consulting', account_700, 2, BigDecimal('500'), BigDecimal('21'), 1 ],
               [ 'Travel', account_700, 1, BigDecimal('80'), BigDecimal('6'), 2 ] ])
    expect(copy.lines.map(&:id) & original.lines.map(&:id)).to be_empty
  end

  it 'copies the analytical annotations of the lines' do
    annotation = copy.lines.first.analytical_annotations.sole

    expect(annotation).to have_attributes(analytical_axis: axis, analytical_account: analytical_account)
    expect(copy.lines.second.analytical_annotations).to be_empty
    expect(original.lines.first.analytical_annotations.count).to eq(1)
  end

  it 'duplicates a supplier invoice too' do
    supplier_invoice = create(:invoice, invoice_type: :supplier, partner: create(:partner, :supplier), fiscal_year: fiscal_year, journal: purchase_journal)
    create(:invoice_line, invoice: supplier_invoice, account: account_604, unit_price: '100.00', vat_rate: '21.00', position: 1)

    result = described_class.call(invoice: supplier_invoice)

    expect(result).to be_success
    expect(result[:invoice]).to have_attributes(invoice_type: 'supplier', journal: purchase_journal)
  end

  it 'duplicates a draft or a cancelled invoice' do
    original.update_columns(status: Accounting::Invoice.statuses[:cancelled])
    expect(described_class.call(invoice: original)).to be_success
  end

  it 'takes the due date from the payment terms of the partner when the original had none' do
    original.update_columns(due_date: nil)
    expect(copy.due_date).to eq(Date.current + 45)
  end

  it 'refuses a credit note' do
    note = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal,
                  document_type: :credit_note, credited_invoice: original)
    result = described_class.call(invoice: note)

    expect(result).to be_failure
    expect(result.message).to be_present
  end

  it 'refuses when no fiscal year is open, creating nothing' do
    fiscal_year.update!(status: :closed, closed_at: Time.current)

    expect { @result = described_class.call(invoice: original) }.not_to change(Accounting::Invoice, :count)
    expect(@result).to be_failure
    expect(@result.message).to be_present
  end

  it 'is all or nothing: a failure while copying the annotations leaves no invoice and no line behind' do
    allow(Accounting::InvoiceLineAnnotation).to receive(:create!).and_raise(StandardError, 'boom')
    lines_before = Accounting::InvoiceLine.count

    result = nil
    expect { result = described_class.call(invoice: original) }.not_to change(Accounting::Invoice, :count)

    expect(result).to be_failure
    expect(Accounting::InvoiceLine.count).to eq(lines_before)
  end
end
