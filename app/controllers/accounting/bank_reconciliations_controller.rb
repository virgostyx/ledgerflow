class Accounting::BankReconciliationsController < ApplicationController
  def show
    authorize :bank_reconciliation, policy_class: Accounting::BankReconciliationsPolicy
    @pagy, @pending_transactions = pagy(Accounting::BankTransaction.pending.filter_by(filter_params)
                                          .includes(bank_account: :journal)
                                          .order(transaction_date: :desc))
    open_invoices = Accounting::Invoice.customer.posted.where.not(invoice_number: nil).to_a
    @suggestions  = @pending_transactions.index_with do |tx|
      Accounting::MatchBankTransaction.call(transaction: tx, open_invoices: open_invoices)
    end
    @bank_accounts = Accounting::BankAccount.where(active: true).order(:label_fr)
    @accounts      = Accounting::Account.where(is_leaf: true).order(:code)
  end

  def allocate
    authorize :bank_reconciliation, :show?, policy_class: Accounting::BankReconciliationsPolicy
    @transaction = Accounting::BankTransaction.pending.find_by(id: params[:bank_transaction_id])
    unless @transaction&.credit?
      return redirect_to accounting_bank_reconciliation_path, alert: t("accounting.bank_reconciliation.not_allocatable")
    end

    @invoices = Accounting::Invoice.customer.posted.includes(:partner).order(:partner_id, :due_date, :id)
  end

  def update
    authorize :bank_reconciliation, policy_class: Accounting::BankReconciliationsPolicy

    if bank_params[:camt_file].present?
      handle_camt_import
    elsif bank_params[:ignore].present?
      handle_ignore
    elsif bank_params[:allocations].present?
      handle_allocations
    elsif bank_params[:accept_suggestion].present?
      handle_accept_suggestion
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
    fiscal_year = Accounting::FiscalYear.current

    result = Accounting::ReconcileBankTransaction.call(
      transaction: transaction,
      account_id:  bank_params[:account_id],
      fiscal_year: fiscal_year,
      label:       bank_params[:label]
    )

    redirect_for(result)
  end

  def handle_ignore
    transaction = Accounting::BankTransaction.pending.find_by(id: bank_params[:bank_transaction_id])
    if transaction
      transaction.ignored!
      redirect_to accounting_bank_reconciliation_path, notice: t("accounting.bank_reconciliation.ignored")
    else
      redirect_to accounting_bank_reconciliation_path, alert: t("accounting.bank_reconciliation.not_pending")
    end
  end

  # Blank or zero amounts are skipped; the service checks the rest (sum, partner, positivity).
  def handle_allocations
    transaction = Accounting::BankTransaction.pending.find_by(id: bank_params[:bank_transaction_id])
    return redirect_to accounting_bank_reconciliation_path, alert: t("accounting.bank_reconciliation.not_pending") unless transaction

    back = allocate_accounting_bank_reconciliation_path(bank_transaction_id: transaction.id)
    allocations = parse_allocations
    return redirect_to back, alert: t("accounting.bank_reconciliation.invalid_amount") unless allocations
    return redirect_to back, alert: t("accounting.bank_reconciliation.invalid_invoice") if allocations.any? { |invoice, _| invoice.nil? }

    result = Accounting::BookInvoiceReceipt.call(transaction: transaction, allocations: allocations,
                                                 fiscal_year: Accounting::FiscalYear.current)
    redirect_for(result, failure_path: back)
  end

  # [[invoice_or_nil, amount], ...] without empty rows; nil when an amount cannot be parsed.
  def parse_allocations
    raw = bank_params[:allocations].to_unsafe_h.transform_values do |value|
      BigDecimal(value.to_s.strip.tr(",", ".").presence || "0", exception: false)
    end
    return if raw.values.any? { |amount| amount.nil? || !amount.finite? }

    invoices = Accounting::Invoice.customer.posted.where(id: raw.keys).index_by { |i| i.id.to_s }
    raw.reject { |_, amount| amount.zero? }.map { |id, amount| [ invoices[id], amount ] }
  end

  # The suggestion is recomputed server-side; the client only says "accept".
  def handle_accept_suggestion
    transaction = Accounting::BankTransaction.pending.find(bank_params[:bank_transaction_id])
    result = Accounting::AcceptBankSuggestion.call(transaction: transaction)
    return redirect_to accounting_bank_reconciliation_path, alert: t("accounting.bank_reconciliation.no_suggestion") unless result

    redirect_for(result)
  end

  def redirect_for(result, failure_path: accounting_bank_reconciliation_path)
    if result.success?
      redirect_to accounting_bank_reconciliation_path, notice: t("accounting.bank_reconciliation.reconciled")
    else
      redirect_to failure_path, alert: result.message
    end
  end

  def bank_params
    @bank_params ||= params.fetch(:bank_reconciliation, {})
  end
end
