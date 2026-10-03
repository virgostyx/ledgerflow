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

    {
      "booking the movement on an account" => -> { { account_id: counterpart.id, label: "Receipt" } },
      "accepting the suggestion"           => -> { { accept_suggestion: "1" } },
      "paying a supplier invoice"          => -> { { pay_invoice_id: 0 } },
      "allocating a receipt to invoices"   => -> { { allocations: { "0" => "100" } } }
    }.each do |label, params|
      it "refuses #{label}: nothing is booked and the movement stays pending" do
        expect { reconcile(instance_exec(&params)) }.not_to change(Accounting::JournalEntry, :count)

        expect(transaction.reload).to be_pending
        expect(response).to redirect_to(accounting_root_path)
      end
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
