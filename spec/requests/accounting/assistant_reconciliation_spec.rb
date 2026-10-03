require "rails_helper"

# F01 review: an assistant reconciles (spec §4) but validates nothing. Every reconciliation action that books and
# validates a payment entry needs the right to validate; importing, keying in and ignoring a movement do not.
# (F02 will let the assistant's reconciliation produce drafts instead; until then the prudent behaviour is a refusal.)
RSpec.describe "Reconciliation by an assistant", type: :request do
  include_context "with_open_fiscal_year"

  let(:assistant)  { create(:user, role: :auditor) } # the global role no longer matters
  let(:accountant) { create(:user, role: :accountant) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }

  let!(:bank_gl)      { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let!(:bank_account) { create(:bank_account, journal: bank_journal) }
  let!(:counterpart)  { create(:account, code: "400000", label_fr: "Customers", account_type: :asset, normal_balance: :debit) }
  let!(:transaction)  { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal("100.00")) }

  def reconcile(params) = patch(accounting_bank_reconciliation_path, params: { bank_reconciliation: { bank_transaction_id: transaction.id }.merge(params) })

  context "as an assistant" do
    before { sign_in assistant }

    # Booking a line produces a DRAFT for someone who cannot validate (F02): the payment entry exists, the line is matched, and an
    # accountant validates it. Paying a supplier invoice settles by lettering, which needs a validated entry: still refused.
    it "books a line on an account as a draft, which an accountant validates" do
      expect { reconcile(account_id: counterpart.id, label: "Receipt") }.to change(Accounting::JournalEntry.draft, :count).by(1)

      expect(transaction.reload).to be_matched
      expect(Accounting::JournalEntry.posted.count).to eq(0)
    end

    it "allocates a receipt to invoices as a draft, the invoices staying unpaid until validation" do
      invoice = create(:invoice, :customer, :posted, fiscal_year: fiscal_year).tap { |i| i.update_columns(total_incl_vat: BigDecimal("100")) }
      create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) unless Accounting::Account.exists?(code: "400000")

      reconcile(allocations: { invoice.id.to_s => "100" })

      expect(transaction.reload).to be_matched
      expect(invoice.reload).to be_posted
    end

    it "pays a supplier invoice as a draft only when it is the whole invoice (a deposit settles by allocation: refused)" do
      supplier_invoice = create(:invoice, :supplier, :posted, fiscal_year: fiscal_year).tap { |i| i.update_columns(total_incl_vat: BigDecimal("100")) }
      create(:account, code: "440000", label_fr: "Fournisseurs", account_type: :liability, normal_balance: :credit) unless Accounting::Account.exists?(code: "440000")
      debit = create(:bank_transaction, bank_account: bank_account, amount: -40)

      expect { patch accounting_bank_reconciliation_path, params: { bank_reconciliation: { bank_transaction_id: debit.id, pay_invoice_id: supplier_invoice.id, invoice_amount: "40" } } }
        .not_to change(Accounting::JournalEntry, :count)

      expect(debit.reload).to be_pending
    end

    it "still imports a statement" do
      file = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/sample_camt.xml"), "application/xml")

      expect { patch accounting_bank_reconciliation_path, params: { bank_reconciliation: { bank_account_id: bank_account.id, camt_file: file } } }
        .to change(Accounting::BankTransaction, :count).by(2)
    end

    it "still ignores a movement" do
      reconcile(ignore: "1")

      expect(transaction.reload).to be_ignored
    end

    it "still sees the reconciliation screen" do
      get accounting_bank_reconciliation_path

      expect(response).to have_http_status(:ok)
    end
  end

  context "as an accountant" do
    before { sign_in accountant }

    it "books the movement, which validates the payment entry" do
      expect { reconcile(account_id: counterpart.id, label: "Receipt") }.to change(Accounting::JournalEntry.posted, :count).by(1)

      expect(transaction.reload).to be_reconciled
    end
  end
end
