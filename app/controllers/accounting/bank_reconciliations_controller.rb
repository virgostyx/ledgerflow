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

    if reconcile_params[:camt_file].present?
      handle_camt_import
    else
      handle_reconciliation
    end
  end

  private

  def handle_camt_import
    bank_account = Accounting::BankAccount.find(reconcile_params[:bank_account_id])
    xml = reconcile_params[:camt_file].read
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
    transaction = Accounting::BankTransaction.find(reconcile_params[:bank_transaction_id])
    fiscal_year = Accounting::FiscalYear.find_by(status: :open)

    result = Accounting::ReconcileBankTransaction.call(
      transaction: transaction,
      account_id:  reconcile_params[:account_id],
      fiscal_year: fiscal_year,
      label:       reconcile_params[:label]
    )

    if result.success?
      redirect_to accounting_bank_reconciliation_path,
                  notice: t("accounting.bank_reconciliation.reconciled")
    else
      redirect_to accounting_bank_reconciliation_path, alert: result.message
    end
  end

  def reconcile_params
    params.require(:bank_reconciliation).permit(
      :bank_transaction_id, :account_id, :label,
      :bank_account_id, :camt_file
    )
  end
end
