require 'rails_helper'

# Scenario: funds land on 580000, a purchase is settled from the cash journal, an OD entry moves the funds
# (credit 580000, debit cash, residual on 499000). Both groups are lettered through the UI.
RSpec.describe 'Lettering workflow', type: :system, js: true do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:transit)    { create(:account, code: '580000', label_fr: 'Virements internes', account_class: 5, account_type: :asset) }
  let!(:suspense)   { create(:account, code: '499000', label_fr: "Comptes d'attente", account_class: 4, account_type: :asset) }
  let(:accountant)  { create(:user, role: :accountant) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  let(:supplier)         { create(:partner, :supplier) }
  let(:purchase_journal) { create(:journal, :purchase) }
  let(:cash_journal)     { create(:journal, :cash) }
  let(:bank_journal)     { create(:journal, :bank) }
  let(:od_journal)       { create(:journal, code: 'OD', label_fr: 'Operations diverses', journal_type: :misc) }
  let(:invoice) do
    create(:invoice, :with_lines, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, journal: purchase_journal)
  end

  # Posts a balanced entry; lines are [account, debit, credit, partner]. JS specs run without a wrapping
  # transaction, so the double-entry trigger is deferred inside one of our own and checked at commit.
  def post_entry(journal, reference, lines)
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
      entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year, reference: reference)
      lines.map do |account, debit, credit, partner|
        create(:journal_entry_line, journal_entry: entry, account: account, partner: partner,
               debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
      end
    end
  end

  def pick_account(account)
    visit new_accounting_lettering_path
    select account.full_label, from: 'account_id'
    click_button 'Show lines'
  end

  before do
    Accounting::PostInvoice.call(invoice: invoice)
    login_as accountant, scope: :user
  end

  it 'letters the supplier invoice against the cash settlement, then the funds on 580000' do
    payable = invoice.reload.journal_entry.lines.find_by!(account: account_440)
    total   = payable.credit
    funds   = total + 100

    cash_line = post_entry(cash_journal, 'CSH/0001', [ [ account_440, total, 0, supplier ], [ account_570, 0, total, nil ] ]).first
    bank_line = post_entry(bank_journal, 'BNQ/0001', [ [ transit, funds, 0, nil ], [ account_550, 0, funds, nil ] ]).first
    od_line   = post_entry(od_journal, 'OD/0001', [ [ transit, 0, funds, nil ], [ account_570, total, 0, nil ],
                                                    [ suspense, 100, 0, nil ] ]).first

    # 1. Supplier: one line alone does not balance, the button stays disabled and shows the gap.
    pick_account(account_440)
    check "line_ids_#{payable.id}"
    expect(page).to have_css('[data-lettering-total-target="difference"]', text: "-#{format('%.2f', total)}")
    expect(page).to have_button('Letter selected lines', disabled: true)

    check "line_ids_#{cash_line.id}"
    expect(page).to have_css('[data-lettering-total-target="difference"]', text: '0.00')
    click_button 'Letter selected lines'

    expect(page).to have_content('Lines lettered (AA)')
    expect(invoice.reload).to be_paid
    expect(page).to have_content('No unlettered lines on this account.')

    # 2. Funds on 580000: the OD credit against the bank line.
    pick_account(transit)
    check "line_ids_#{od_line.id}"
    check "line_ids_#{bank_line.id}"
    click_button 'Letter selected lines'

    expect(page).to have_content('Lines lettered (AA)')
    expect([ od_line, bank_line ].map { |l| l.reload.lettering_id }.uniq.size).to eq(1)
    expect(Accounting::Lettering.count).to eq(2)

    # 3. Removing the supplier lettering reopens the invoice.
    pick_account(account_440)
    click_button 'Remove'

    expect(page).to have_content('Lettering AA removed')
    expect(invoice.reload).to be_posted
  end
end
