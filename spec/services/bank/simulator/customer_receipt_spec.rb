require 'rails_helper'

RSpec.describe Bank::Simulator::CustomerReceipt, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:invoice) do
    create(:invoice, :customer, :posted).tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
  end

  def import(xml)
    Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
  end

  it 'books a full receipt that the matcher recognises' do
    import(described_class.call(invoice: invoice, bank_account: bank_account))

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('1210'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx).target).to eq(invoice)
  end

  it 'supports a partial payment (suggested with medium confidence)' do
    import(described_class.call(invoice: invoice, bank_account: bank_account, amount: BigDecimal('500')))

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('500'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to have_attributes(target: invoice, confidence: :medium)
  end

  it 'supports a transfer without communication (not matched)' do
    import(described_class.call(invoice: invoice, bank_account: bank_account, communication: false))

    expect(Accounting::MatchBankTransaction.call(transaction: Accounting::BankTransaction.sole)).to be_nil
  end

  it 'refuses a supplier invoice' do
    supplier_invoice = create(:invoice, :supplier, :posted)

    expect { described_class.call(invoice: supplier_invoice, bank_account: bank_account) }
      .to raise_error(ArgumentError, /customer invoice/)
  end

  it 'refuses an invoice that is not posted' do
    draft = create(:invoice, :customer, :draft)

    expect { described_class.call(invoice: draft, bank_account: bank_account) }
      .to raise_error(ArgumentError, /not posted/)
  end

  it 'can be repeated with distinct references (duplicate payment)' do
    2.times { import(described_class.call(invoice: invoice, bank_account: bank_account)) }
    expect(Accounting::BankTransaction.count).to eq(2)
  end
end
