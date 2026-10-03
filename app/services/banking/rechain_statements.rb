# The opening balance of a statement must be the closing balance of the one before it (F02). Recomputed for the whole account
# after each import, so that statements arriving out of order are checked against their real neighbour: the first statement has
# nothing to chain to (nil), a break keeps its amount, a statement that repairs it clears it.
# => the warnings for the statements that do not follow (the ones just imported and any whose state changed)
class Banking::RechainStatements
  def self.call(bank_account:)
    ordered = Accounting::BankStatement.where(bank_account: bank_account)
                                       .order(Arel.sql("COALESCE(new_balance_date, old_balance_date), id")).to_a
    warnings = []
    ordered.each_with_index do |statement, index|
      previous = ordered[index - 1] if index.positive?
      gap = previous && statement.old_balance - (previous.new_balance || previous.old_balance)
      changed = statement.chain_gap != gap
      statement.update!(chain_gap: gap) if changed
      warnings << message(bank_account, statement, previous, gap) if gap&.nonzero? && (changed || statement.created_at > 1.minute.ago)
    end
    warnings
  end

  def self.message(account, statement, previous, gap)
    iban = account.iban.to_s
    I18n.t("banking.import.chain_broken", account: iban.length > 8 ? "#{iban[0, 4]}#{'*' * (iban.length - 8)}#{iban.last(4)}" : iban, sequence: statement.sequence,
                                          gap: gap.to_s("F"), previous: (previous.new_balance || previous.old_balance).to_s("F"))
  end
  private_class_method :message
end
