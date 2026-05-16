class Accounting::ReconcileBankTransaction
  extend LightService::Organizer

  def self.call(transaction:, account_id:, fiscal_year:, label: nil)
    return already_reconciled_failure if transaction.reconciled?

    result = nil
    ApplicationRecord.transaction do
      result = with(
        transaction: transaction,
        account_id:  account_id,
        fiscal_year: fiscal_year,
        label:       label
      ).reduce(
        Accounting::Actions::CreateBankJournalEntry,
        Accounting::Actions::MarkTransactionReconciled
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(transaction: transaction)
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.already_reconciled_failure
    ctx = LightService::Context.make
    ctx.fail!(I18n.t("accounting.errors.already_reconciled"))
    ctx
  end
  private_class_method :already_reconciled_failure
end
