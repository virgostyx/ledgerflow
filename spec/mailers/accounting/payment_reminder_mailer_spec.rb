require 'rails_helper'

RSpec.describe Accounting::PaymentReminderMailer, type: :mailer do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:partner) { create(:partner, name: 'Sodexo Belgium') }

  before { entity.update!(legal_name: 'Acme Consulting', legal_form: 'SRL') }

  def posted_invoice(due_days_ago:, unit_price: '1000.00')
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal,
                 due_date: Date.current - due_days_ago)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, description: 'Consulting',
           unit_price: unit_price, vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  let!(:older)  { posted_invoice(due_days_ago: 40, unit_price: '1000.00') } # 1210.00
  let!(:recent) { posted_invoice(due_days_ago: 5, unit_price: '500.00') }   # 605.00

  def reminder(level: 1)
    create(:payment_reminder, partner: partner, level: level, recipient: 'accounts@sodexo.example',
           subject: 'Payment reminder').tap do |r|
      r.items.create!(invoice: older, amount_due: 1210)
      r.items.create!(invoice: recent, amount_due: 605)
    end
  end

  def money(amount) = Accounting::MoneyPresenter.new(amount).format

  let(:mail) { described_class.payment_reminder(reminder) }
  def text_of(mail) = mail.text_part.body.decoded

  let(:body) { text_of(mail) }

  it 'is addressed to the recipient with the stored subject, in the name of the entity' do
    expect(mail.to).to eq([ 'accounts@sodexo.example' ])
    expect(mail.subject).to eq('Payment reminder')
    expect(mail[:from].to_s).to include('Acme Consulting')
  end

  it 'lists every invoice with its number, due date, days overdue and the amount still due' do
    expect(body).to include(older.invoice_number, recent.invoice_number, '40 days overdue', '5 days overdue', money(1210), money(605))
  end

  it 'gives the total due' do
    expect(body).to include(money(1815))
  end

  it 'attaches the PDF of each invoice' do
    names = mail.attachments.map(&:filename)
    expect(names).to contain_exactly("#{older.invoice_number.tr('/', '-')}.pdf", "#{recent.invoice_number.tr('/', '-')}.pdf")
    expect(mail.attachments).to all(satisfy { |a| a.mime_type == 'application/pdf' && a.body.to_s.start_with?('%PDF') })
  end

  it 'is signed with the name of the entity' do
    expect(body).to include('Kind regards', 'Acme Consulting')
  end

  describe 'the wording of each level' do
    it 'is a friendly reminder at level 1, that may be ignored if already paid' do
      expect(text_of(described_class.payment_reminder(reminder(level: 1)))).to include('oversight').and include('disregard')
    end

    it 'refers to the earlier reminder at level 2' do
      expect(text_of(described_class.payment_reminder(reminder(level: 2)))).to include('second reminder').and include('earlier reminder')
    end

    it 'is a formal notice at level 3' do
      expect(text_of(described_class.payment_reminder(reminder(level: 3)))).to include('formal notice').and include('further steps')
    end
  end
end
