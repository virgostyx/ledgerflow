class Accounting::BankReconciliationsController < ApplicationController
  def show
    authorize :bank_reconciliation, policy_class: Accounting::BankReconciliationsPolicy
    @pending_transactions = Accounting::BankTransaction.pending
                                .includes(bank_account: :journal)
                                .order(transaction_date: :desc)
    @bank_accounts = Accounting::BankAccount.where(active: true).order(:label_fr)
    @accounts      = Accounting::Account.where(is_leaf: true).order(:code)
  end

  def update
    authorize :bank_reconciliation, policy_class: Accounting::BankReconciliationsPolicy

    if bank_params[:camt_file].present?
      handle_camt_import
    else
      handle_reconciliation
    end
  end

  private

  def handle_camt_import
    bank_account = Accounting::BankAccount.find(bank_params[:bank_account_id])
    xml = bank_params[:camt_file]&.read
    result = Accounting::ImportCamtStatement.call(xml: xml, bank_account: bank_account)

    if result.success?
      redirect_to accounting_bank_reconciliation_path,
                  notice: t("accounting.bank_reconciliation.imported",
                            count: result[:imported_count])
    else
      redirect_to accounting_bank_reconciliation_path, alert: result.message
    end
  end

  def handle_reconciliation
    transaction = Accounting::BankTransaction.find(bank_params[:bank_transaction_id])
    fiscal_year = Accounting::FiscalYear.find_by(status: :open)

    result = Accounting::ReconcileBankTransaction.call(
      transaction: transaction,
      account_id:  bank_params[:account_id],
      fiscal_year: fiscal_year,
      label:       bank_params[:label]
    )

    if result.success?
      redirect_to accounting_bank_reconciliation_path,
                  notice: t("accounting.bank_reconciliation.reconciled")
    else
      redirect_to accounting_bank_reconciliation_path, alert: result.message
    end
  end

  def bank_params
    @bank_params ||= params.fetch(:bank_reconciliation, {})
  end
end
