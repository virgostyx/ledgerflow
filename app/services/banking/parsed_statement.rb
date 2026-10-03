# One account's statement, as read from a file. `integrity_ok?`: old balance + movements = new balance (an empty
# statement has no new balance). A gap does not refuse the file, it marks the statement "to review".
Banking::ParsedStatement = Struct.new(
  :iban, :account_number, :currency, :holder, :description, :sequence,
  :old_balance, :old_balance_date, :new_balance, :new_balance_date,
  :lines, :messages, :header, :addressee, :account_structure,
  keyword_init: true
) do
  def empty? = lines.empty? && new_balance.nil?

  def expected_new_balance = old_balance + lines.sum(BigDecimal("0"), &:amount)

  def integrity_gap = new_balance ? new_balance - expected_new_balance : BigDecimal("0")

  def integrity_ok? = integrity_gap.zero?
end
