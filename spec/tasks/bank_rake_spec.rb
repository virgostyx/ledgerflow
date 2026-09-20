require 'rails_helper'
require 'rake'

RSpec.describe 'bank rake tasks' do
  include_context 'with_open_fiscal_year'

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?('bank:fees')
  end

  let(:bank_account) { create(:bank_account) }

  def run(task, *args)
    Rake::Task[task].reenable
    Rake::Task[task].invoke(*args.map(&:to_s))
  end

  def customer_invoice(number = 'RK-1', total = 1000)
    create(:invoice, :customer, :posted, fiscal_year: fiscal_year, invoice_number: number)
      .tap { |i| i.update_columns(total_incl_vat: BigDecimal(total.to_s)) }
  end

  it 'bank:receipt imports the receipt of a customer invoice' do
    invoice = customer_invoice

    expect { run('bank:receipt', invoice.id, bank_account.id) }
      .to output(/Imported 1 transaction/).to_stdout
      .and change(Accounting::BankTransaction, :count).by(1)
  end

  it 'bank:receipt refuses a supplier invoice with an error message and imports nothing' do
    supplier_invoice = create(:invoice, :supplier, :posted, fiscal_year: fiscal_year)

    expect { expect { run('bank:receipt', supplier_invoice.id, bank_account.id) }.to raise_error(SystemExit) }
      .to output(/not a customer invoice/).to_stderr
    expect(Accounting::BankTransaction.count).to eq(0)
  end

  it 'bank:grouped_receipt imports one transfer for several invoices' do
    partner  = create(:partner)
    invoices = %w[RK-A RK-B].map { |n| customer_invoice(n).tap { |i| i.update_columns(partner_id: partner.id) } }

    expect { run('bank:grouped_receipt', bank_account.id, invoices.map(&:id).join(' ')) }
      .to output(/Imported 1 transaction/).to_stdout
    expect(Accounting::BankTransaction.sole.amount).to eq(BigDecimal('2000'))
  end

  it 'bank:pay_batch imports the debit of a generated batch and refuses a draft one' do
    batch = create(:payment_batch, :generated, bank_account: bank_account, total_amount: BigDecimal('300'))
    expect { run('bank:pay_batch', batch.id) }.to output(/Imported 1 transaction/).to_stdout

    draft = create(:payment_batch, status: :draft, bank_account: bank_account)
    expect { expect { run('bank:pay_batch', draft.id) }.to raise_error(SystemExit) }
      .to output(/not generated/).to_stderr
  end

  it 'bank:fees imports a fee, with a default or a given amount' do
    expect { run('bank:fees', bank_account.id) }.to output(/Imported 1/).to_stdout
    expect { run('bank:fees', bank_account.id, '12.30') }.to output(/Imported 1/).to_stdout

    expect(Accounting::BankTransaction.pluck(:amount)).to contain_exactly(BigDecimal('-4.50'), BigDecimal('-12.30'))
  end

  it 'bank:withdrawal imports a cash withdrawal as a debit, whatever the sign given' do
    expect { run('bank:withdrawal', bank_account.id, '500') }.to output(/Imported 1/).to_stdout
    expect { run('bank:withdrawal', bank_account.id, '-200') }.to output(/Imported 1/).to_stdout

    expect(Accounting::BankTransaction.pluck(:amount)).to contain_exactly(BigDecimal('-500'), BigDecimal('-200'))
    tx = Accounting::BankTransaction.order(:id).first
    expect(tx).to be_debit
    expect(tx.description).to eq('Cash withdrawal')
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to be_nil
  end

  it 'bank:transfer imports an unidentified transfer' do
    expect { run('bank:transfer', bank_account.id, '1200') }.to output(/Imported 1/).to_stdout

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('1200'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to be_nil
  end
end
