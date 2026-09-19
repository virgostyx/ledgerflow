require 'rails_helper'

RSpec.describe Bank::Simulator::GroupedReceipt, type: :service do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let!(:fiscal_year) { create(:fiscal_year, status: :open) }
  let(:partner)      { create(:partner) }
  let(:invoices) do
    [ [ '2026-0041', 1000 ], [ '2026-0043', 500 ] ].map do |number, total|
      create(:invoice, :customer, :posted, partner: partner, fiscal_year: fiscal_year, invoice_number: number)
        .tap { |i| i.update_columns(total_incl_vat: BigDecimal(total.to_s)) }
    end
  end

  def import(xml)
    Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)
  end

  it 'books one transfer for the sum, which the matcher recognises' do
    import(described_class.call(invoices: invoices, bank_account: bank_account))

    tx = Accounting::BankTransaction.sole
    expect(tx.amount).to eq(BigDecimal('1500'))
    expect(Accounting::MatchBankTransaction.call(transaction: tx)).to have_attributes(kind: :invoices, target: invoices)
  end

  it 'refuses fewer than two invoices' do
    expect { described_class.call(invoices: invoices.first(1), bank_account: bank_account) }
      .to raise_error(ArgumentError, /at least two/)
  end

  it 'refuses invoices of different partners' do
    invoices.last.update_columns(partner_id: create(:partner).id)
    expect { described_class.call(invoices: invoices, bank_account: bank_account) }
      .to raise_error(ArgumentError, /same partner/)
  end

  it 'refuses a supplier or unposted invoice' do
    invoices.last.update_columns(status: Accounting::Invoice.statuses[:draft])
    expect { described_class.call(invoices: invoices, bank_account: bank_account) }
      .to raise_error(ArgumentError, /open customer invoices/)
  end
end
