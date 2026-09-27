# R06 (docs/dev/reports/spec.md §8): B (relevé) + BN (comptabilisé, absent du relevé)
# − SN (sur le relevé, non comptabilisé) doit égaler A (solde comptable réel), à
# `as_of` — rétroactif comme R04/R05.
#
# Pas de notion de "relevé bancaire" groupé dans ce dépôt (docs/dev/reports/00-audit.md
# §1) : `accounting_bank_transactions` est plat, sans solde d'ouverture/clôture par
# relevé. B est donc reconstruit comme la somme de toutes les transactions datées
# jusqu'à `as_of` — le chaînage entre relevés (rupture) n'est pas modélisable ici et
# reste hors périmètre v1 (voir docs/dev/reports/QUESTIONS.md).
class Accounting::BankReconciliationQuery
  Item = Struct.new(:date, :label, :reference, :amount, :journal_entry_id, keyword_init: true)
  Result = Struct.new(:statement_balance, :accounting_balance, :bn, :sn, :bn_total, :sn_total,
                      :expected_balance, :gap, keyword_init: true)

  def initialize(bank_account:, as_of: Date.current)
    @bank_account = bank_account
    @as_of        = as_of
    @gl_account   = bank_account.journal.default_account
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
               expected_balance: expected, gap: accounting_balance - expected)
  end

  private

  def statement_balance_as_of
    @bank_account.transactions.where("transaction_date <= ?", @as_of).sum(:amount)
  end

  def accounting_balance_as_of
    lines = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(account: @gl_account)
      .where(accounting_journal_entries: { status: Accounting::JournalEntry.statuses[:posted] })
      .where("accounting_journal_entries.entry_date <= ?", @as_of)
    lines.sum(:debit) - lines.sum(:credit)
  end

  # Booked on the GL account, but not (yet, as of `as_of`) linked to any statement transaction.
  def booked_not_on_statement
    linked_entry_ids = @bank_account.transactions.where("transaction_date <= ?", @as_of)
      .where.not(journal_entry_id: nil).pluck(:journal_entry_id)

    Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(account: @gl_account)
      .where(accounting_journal_entries: { status: Accounting::JournalEntry.statuses[:posted] })
      .where("accounting_journal_entries.entry_date <= ?", @as_of)
      .where.not(journal_entry_id: linked_entry_ids)
      .map do |line|
        Item.new(date: line.journal_entry.entry_date, label: line.label, reference: line.journal_entry.reference,
                  amount: line.debit - line.credit, journal_entry_id: line.journal_entry_id)
      end
  end

  # On the statement as of `as_of`, but not linked to a booked entry.
  def on_statement_not_booked
    @bank_account.transactions.where("transaction_date <= ?", @as_of).where(journal_entry_id: nil)
      .map { |tx| Item.new(date: tx.transaction_date, label: tx.description, reference: tx.reference, amount: tx.amount) }
  end
end
