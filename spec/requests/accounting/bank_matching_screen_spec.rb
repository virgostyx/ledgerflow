require "rails_helper"

# F02: the reconciliation screen: indicators, scores, drafts for those who cannot validate, the matched lines and their undoing,
# a rule made from a line, keyboard shortcuts.
RSpec.describe "Bank reconciliation screen (F02)", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user, role: :accountant) }
  let(:assistant)  { create(:user, role: :auditor) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }

  let!(:bank_gl)     { create(:account, code: "550000", label_fr: "Banque", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:receivable)  { create(:account, code: "400000", label_fr: "Clients", account_type: :asset, normal_balance: :debit) }
  let!(:fees)        { create(:account, code: "651100", label_fr: "Frais bancaires") }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account) { create(:bank_account, journal: bank_journal) }
  let(:partner) { create(:partner, name: "DUPONT ET FILS SPRL", iban: CodaBuilder.iban("091012345678")) }
  let(:invoice) { create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: partner).tap { |i| i.update_columns(total_incl_vat: BigDecimal("1210")) } }

  def structured(target) = Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(target.id))
  def line(amount, **attrs) = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal(amount.to_s), **attrs)
  def patch_bank(params) = patch(accounting_bank_reconciliation_path, params: { bank_reconciliation: params })
  def indicator(name) = Nokogiri::HTML(response.body).at_css("#indicator-#{name}")&.text&.strip

  before { sign_in accountant }

  describe "the indicators" do
    it "count the lines imported, the share matched automatically, what is left and how old the oldest is" do
      batch = Accounting::ImportBatch.create!(parser: "coda", file_sha256: "x", result: "imported")
      statement = Accounting::BankStatement.create!(bank_account: bank_account, import_batch: batch, old_balance: 0)
      line(10, statement: statement, transaction_date: Date.current - 10)
      line(20, statement: statement)
      line(30, statement: statement, status: :matched, match_data: { "auto" => true })
      line(40, statement: statement, status: :reconciled)

      get accounting_bank_reconciliation_path

      expect(indicator("imported")).to eq("4")
      expect(indicator("automatic")).to include("25")
      expect(indicator("pending")).to eq("2")
      expect(indicator("oldest")).to include("10")
    end

    it "are not shown while the feature is off" do
      entity.update!(features: entity.features.merge("f02" => false))

      get accounting_bank_reconciliation_path

      expect(indicator("imported")).to be_nil
    end
  end

  describe "the suggestion" do
    it "shows the score and the rule" do
      line(1210, description: structured(invoice))

      get accounting_bank_reconciliation_path

      expect(response.body).to match(/score 100/i)
      expect(response.body).to match(/rule 1/i)
      expect(response.body).to include("Accept")
    end

    it "names a supplier invoice or a bank rule it points at" do
      Accounting::BankRule.create!(name: "Bank fees", condition_type: "contains", condition_value: "frais de tenue", account: fees, score: 85)
      line(-12.5, description: "FRAIS DE TENUE DE COMPTE")

      get accounting_bank_reconciliation_path

      expect(response.body).to include("rule “Bank fees”").or include("rule &quot;Bank fees&quot;").or include("Bank fees")
    end
  end

  describe "accepting a suggestion" do
    let!(:tx) { line(1210, description: structured(invoice)) }

    it "validates the payment when the person can validate" do
      patch_bank(bank_transaction_id: tx.id, accept_suggestion: 1)

      expect(tx.reload).to be_reconciled
      expect(tx.journal_entry).to be_posted
    end

    it "leaves a draft when the person cannot validate (an assistant)" do
      sign_out accountant
      sign_in assistant

      patch_bank(bank_transaction_id: tx.id, accept_suggestion: 1)

      expect(tx.reload).to be_matched
      expect(tx.journal_entry).to be_draft
      expect(invoice.reload).to be_posted
    end

    it "lets an assistant book a line on an account, as a draft" do
      sign_out accountant
      sign_in assistant

      patch_bank(bank_transaction_id: tx.id, account_id: receivable.id, label: "Receipt")

      expect(tx.reload).to be_matched
      expect(tx.journal_entry).to be_draft
    end

    it "no longer sends an assistant away from the supplier payment form: a whole invoice becomes a draft (see supplier_draft_spec), a deposit is refused with its reason" do
      sign_out accountant
      sign_in assistant
      payable = create(:invoice, :supplier, :posted, fiscal_year: fiscal_year, partner: create(:partner, :supplier)).tap { |i| i.update_columns(total_incl_vat: BigDecimal("100")) }
      deposit = line(-40)

      patch_bank(bank_transaction_id: deposit.id, pay_invoice_id: payable.id, invoice_amount: "40")

      expect(deposit.reload).to be_pending
      expect(response).to redirect_to(accounting_bank_reconciliation_path)
      expect(flash[:alert]).to match(/whole invoice|euros/i)
    end
  end

  describe "the matched lines" do
    let!(:tx) { line(1210, description: structured(invoice)) }

    before { Accounting::AcceptBankSuggestion.call(transaction: tx, draft: true) }

    it "are listed with their draft entry and a way to undo" do
      get accounting_bank_reconciliation_path

      expect(response.body).to include("Awaiting validation")
      expect(response.body).to include(accounting_journal_entry_path(tx.reload.journal_entry))
      expect(response.body).to include("Undo")
    end

    it "can be undone by the assistant who may match them: the draft goes, the line is pending again" do
      sign_out accountant
      sign_in assistant

      patch_bank(bank_transaction_id: tx.id, undo: 1)

      expect(tx.reload).to be_pending
      expect(tx.journal_entry).to be_nil
    end
  end

  describe "undoing a validated payment" do
    let!(:tx) { line(1210, description: structured(invoice)) }

    before { Accounting::AcceptBankSuggestion.call(transaction: tx) }

    it "reverses it, with a reason" do
      patch_bank(bank_transaction_id: tx.id, undo: 1, reason: "Wrong customer")

      expect(tx.reload).to be_pending
      expect(invoice.reload).to be_posted
    end

    it "wants a reason" do
      patch_bank(bank_transaction_id: tx.id, undo: 1)

      expect(tx.reload).to be_reconciled
      expect(flash[:alert]).to match(/reason/i)
    end

    it "is refused to a person who cannot reverse an entry" do
      sign_out accountant
      sign_in assistant

      patch_bank(bank_transaction_id: tx.id, undo: 1, reason: "x")

      expect(tx.reload).to be_reconciled
    end
  end

  describe "making a rule from a line" do
    let!(:tx) { line(-12.5, description: "FRAIS DE TENUE DE COMPTE", counterparty_iban: CodaBuilder.iban("737000012345")) }

    it "creates the rule from what the line says, on the chosen account" do
      expect { patch_bank(bank_transaction_id: tx.id, create_rule: 1, account_id: fees.id, rule_name: "Bank fees", rule_action: "book_draft") }
        .to change(Accounting::BankRule, :count).by(1)

      expect(Accounting::BankRule.last).to have_attributes(condition_type: "iban", account: fees, name: "Bank fees", action: "book_draft")
    end

    it "is refused to someone who does not manage the settings" do
      sign_out accountant
      sign_in assistant

      expect { patch_bank(bank_transaction_id: tx.id, create_rule: 1, account_id: fees.id, rule_name: "x") }.not_to change(Accounting::BankRule, :count)
    end

    it "says what is wrong when the rule is invalid" do
      patch_bank(bank_transaction_id: tx.id, create_rule: 1, account_id: fees.id, rule_name: "")

      expect(flash[:alert]).to be_present
    end
  end

  describe "splitting a line across several accounts" do
    let!(:rent) { create(:account, code: "610000", label_fr: "Loyer") }
    let!(:tx) { line(-1000, description: "LOYER ET CHARGES") }

    it "books each row on its account, the screen offering the rows" do
      get accounting_bank_reconciliation_path
      expect(response.body).to include("Split across several accounts")

      patch_bank(bank_transaction_id: tx.id, label: "Rent", splits: { "0" => { account_id: rent.id, amount: "850" }, "1" => { account_id: fees.id, amount: "150,00" }, "2" => { account_id: "", amount: "" } })

      expect(tx.reload).to be_reconciled
      expect(tx.journal_entry.lines.find_by(account: rent).debit).to eq(850)
      expect(tx.journal_entry.lines.find_by(account: fees).debit).to eq(150)
    end

    it "says so when the rows do not add up, or an amount is unreadable, and books nothing" do
      patch_bank(bank_transaction_id: tx.id, splits: { "0" => { account_id: rent.id, amount: "850" } })
      expect(tx.reload).to be_pending
      expect(flash[:alert]).to match(/add up/i)

      patch_bank(bank_transaction_id: tx.id, splits: { "0" => { account_id: rent.id, amount: "abc" } })
      expect(tx.reload).to be_pending
      expect(flash[:alert]).to be_present
    end

    it "gives an assistant a draft" do
      sign_out accountant
      sign_in assistant

      patch_bank(bank_transaction_id: tx.id, splits: { "0" => { account_id: rent.id, amount: "700" }, "1" => { account_id: fees.id, amount: "300" } })

      expect(tx.reload).to be_matched
    end
  end

  describe "the keyboard" do
    it "is wired on the table, with rows and the accept and ignore actions" do
      line(1210, description: structured(invoice))

      get accounting_bank_reconciliation_path

      expect(response.body).to include('data-controller="bank-keys"', "data-bank-keys-target=\"row\"", 'data-bank-keys-action="accept"', 'data-bank-keys-action="ignore"')
    end
  end
end
