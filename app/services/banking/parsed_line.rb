# A movement of a statement, as the bank gave it. `amount` is signed (credit positive). `details` are the globalisation
# detail movements the bank sent behind a total; the total is what counts for the balance.
Banking::ParsedLine = Struct.new(
  :sequence, :detail, :bank_reference, :amount, :value_date, :entry_date, :transaction,
  :structured_type, :structured_communication, :structured_valid, :communication,
  :counterparty_name, :counterparty_iban, :counterparty_account, :counterparty_currency, :counterparty_bic, :counterparty_text,
  :customer_reference, :information, :r_type, :iso_reason, :category_purpose, :purpose, :raw, :details, :fingerprint,
  keyword_init: true
) do
  def credit? = amount.positive?
  def debit? = amount.negative?
end
