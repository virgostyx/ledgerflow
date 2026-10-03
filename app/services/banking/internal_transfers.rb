# A transfer between two bank accounts of the entity (F02) shows as two lines, one on each statement. They are paired when the
# amounts are equal and opposite, the accounts two, the dates within three days, one line names the other account (its IBAN),
# and neither could be the half of another pair (if it could, a person decides). Each half is booked as a draft against the
# transit account 580000 (virements internes) in its own bank's journal; when both are validated, the two transit lines are
# lettered and cancel out. => the number of pairs booked
class Banking::InternalTransfers
  WINDOW = 3 # days

  def self.call(transactions:) = new(transactions).call

  def initialize(transactions)
    @transactions = Array(transactions)
  end

  def call
    @transit = Accounting::Account.find_by(code: Accounting::AccountCodes::INTERNAL_TRANSFERS)
    return 0 unless @transit

    @transactions.count { |transaction| pair(transaction.reload) }
  end

  private

  def pair(transaction)
    return false unless transaction.pending?

    other = the_other_half(transaction)
    return false unless other && the_other_half(other) == transaction

    book(transaction, other)
    true
  end

  # The one line that could be the other half, or nil (none, or several).
  def the_other_half(transaction)
    return unless transaction.currency == "EUR"

    candidates = Accounting::BankTransaction.pending.includes(:bank_account)
                                             .where(currency: "EUR", amount: -transaction.amount)
                                             .where.not(bank_account_id: transaction.bank_account_id)
                                             .where(transaction_date: (transaction.transaction_date - WINDOW)..(transaction.transaction_date + WINDOW))
                                             .select { |other| names_the_other?(transaction, other) }
    candidates.first if candidates.one?
  end

  def names_the_other?(one, other)
    iban = ->(text) { text.to_s.delete(" ").upcase }
    iban.(one.counterparty_iban) == iban.(other.bank_account.iban) || iban.(other.counterparty_iban) == iban.(one.bank_account.iban)
  end

  def book(one, other)
    ApplicationRecord.transaction do
      [ [ one, other ], [ other, one ] ].each do |transaction, pair|
        result = Accounting::ReconcileBankTransaction.call(transaction: transaction, account_id: @transit.id, fiscal_year: Accounting::FiscalYear.current,
                                                           label: I18n.t("banking.match.internal_transfer"), draft: true)
        raise ActiveRecord::Rollback, result.message if result.failure?

        transaction.reload.update!(match_data: { "kind" => "transfer", "pair_id" => pair.id, "auto" => true })
        Accounting::AuditLog.record!(auditable: transaction, action: "bank_transfer_matched", payload: { pair_id: pair.id, amount: transaction.amount.to_s("F") })
      end
    end
  end
end
