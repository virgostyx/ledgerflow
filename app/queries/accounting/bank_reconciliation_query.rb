# R06 (docs/dev/reports/spec.md §8): B (relevé) + BN (comptabilisé, absent du relevé)
# − SN (sur le relevé, non comptabilisé) doit égaler A (solde comptable réel), à
# `as_of` — rétroactif comme R04/R05.
#
# Sans relevé importé (CAMT, CSV, saisie manuelle : `accounting_bank_transactions` est plat), B est
# reconstruit comme la somme des transactions datées jusqu'à `as_of`. Dès qu'un relevé CODA (F02) existe
# jusqu'à `as_of`, B est le solde de clôture du dernier relevé, plus les transactions hors relevé qui le
# suivent : le solde d'ouverture de la banque est enfin connu. Les relevés dont les soldes ne s'enchaînent
# pas, ou qui ne s'additionnent pas, sont listés avec le rapport (`chain_breaks`, `to_review`).
class Accounting::BankReconciliationQuery
  Item = Struct.new(:date, :label, :reference, :amount, :journal_entry_id, keyword_init: true)
  # `currency`: the one of the account, in which the whole reconciliation is done (F11). For an account in a foreign currency, `booked_eur` is what the
  # books carry in EUR and `fx_difference` the exchange difference to report apart: the balance valued at the closing rate of `as_of`, less the euros
  # booked (negative = a loss; nil without a closing rate, never guessed). Both are nil for an account in EUR.
  Result = Struct.new(:statement_balance, :accounting_balance, :bn, :sn, :bn_total, :sn_total,
                      :expected_balance, :gap, :chain_breaks, :to_review, :currency, :booked_eur, :fx_difference, keyword_init: true)

  def initialize(bank_account:, as_of: Date.current)
    @bank_account = bank_account
    @as_of        = as_of
    @gl_account   = bank_account.journal.default_account
    @foreign      = bank_account.currency != "EUR"
  end

  def call
    bn = booked_not_on_statement
    sn = on_statement_not_booked
    bn_total = bn.sum(&:amount)
    sn_total = sn.sum(&:amount)
    statement_balance  = statement_balance_as_of
    accounting_balance = accounting_balance_as_of
    expected = statement_balance + bn_total - sn_total

    Result.new(statement_balance: statement_balance, accounting_balance: accounting_balance,
               bn: bn, sn: sn, bn_total: bn_total, sn_total: sn_total,
               expected_balance: expected, gap: accounting_balance - expected,
               chain_breaks: statements.select(&:chain_broken?), to_review: statements.select(&:to_review?),
               currency: @bank_account.currency, booked_eur: (booked_eur if @foreign), fx_difference: (fx_difference(accounting_balance) if @foreign))
  end

  private

  # The imported statements up to `as_of`, newest first by their closing date.
  def statements
    @statements ||= Accounting::BankStatement.where(bank_account: @bank_account).where("COALESCE(new_balance_date, old_balance_date) <= ?", @as_of)
                                             .order(Arel.sql("COALESCE(new_balance_date, old_balance_date) DESC"), id: :desc).to_a
  end

  def statement_balance_as_of
    last = statements.first
    return @bank_account.transactions.where("transaction_date <= ?", @as_of).sum(:amount) unless last

    closed_on = last.new_balance_date || last.old_balance_date
    (last.new_balance || last.old_balance) +
      @bank_account.transactions.where(statement_id: nil).where("transaction_date > ? AND transaction_date <= ?", closed_on, @as_of).sum(:amount)
  end

  def accounting_balance_as_of
    lines = ledger_lines.where("accounting_journal_entries.entry_date <= ?", @as_of)
    @foreign ? lines.where(currency: @bank_account.currency).sum(:amount_currency) : lines.sum(:debit) - lines.sum(:credit)
  end

  def ledger_lines
    Accounting::JournalEntryLine.joins(:journal_entry).where(account: @gl_account)
                                .where(accounting_journal_entries: { status: Accounting::JournalEntry.ledger_status_values })
  end

  def booked_eur
    lines = ledger_lines.where("accounting_journal_entries.entry_date <= ?", @as_of)
    lines.sum(:debit) - lines.sum(:credit)
  end

  def fx_difference(balance)
    Fx::Convert.to_eur(balance, Fx::RateFor.closing(@bank_account.currency, @as_of)) - booked_eur
  rescue Fx::MissingRate
    nil
  end

  # Booked on the GL account, but not (yet, as of `as_of`) linked to any statement transaction.
  def booked_not_on_statement
    linked_entry_ids = @bank_account.transactions.where("transaction_date <= ?", @as_of)
      .where.not(journal_entry_id: nil).pluck(:journal_entry_id)

    lines = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(account: @gl_account)
      .where(accounting_journal_entries: { status: Accounting::JournalEntry.ledger_status_values })
      .where("accounting_journal_entries.entry_date <= ?", @as_of)
      .where.not(journal_entry_id: linked_entry_ids)
    lines = lines.where("accounting_journal_entries.entry_date > ?", opening_date) if opening_date
    lines
      .map do |line|
        Item.new(date: line.journal_entry.entry_date, label: line.label, reference: line.journal_entry.reference,
                  amount: (@foreign ? line.amount_currency.to_d : line.debit - line.credit), journal_entry_id: line.journal_entry_id)
      end
  end

  # With statements, the bank's opening balance (of the earliest one) already holds everything before it: only what follows is
  # compared line by line. A ledger that opened differently from the bank shows as the gap.
  def opening_date = statements.last&.old_balance_date

  # On the statement as of `as_of`, but not linked to a booked entry: no entry yet, or only a draft (F02: a matched line whose
  # payment entry waits to be validated is still not in the ledger).
  def on_statement_not_booked
    transactions = @bank_account.transactions.left_joins(:journal_entry).where("accounting_bank_transactions.transaction_date <= ?", @as_of)
                                .where("accounting_bank_transactions.journal_entry_id IS NULL OR accounting_journal_entries.status <> ?", Accounting::JournalEntry.statuses[:posted])
    transactions = transactions.where("accounting_bank_transactions.transaction_date > ?", opening_date) if opening_date
    transactions.map { |tx| Item.new(date: tx.transaction_date, label: tx.description, reference: tx.reference, amount: tx.amount) }
  end
end
