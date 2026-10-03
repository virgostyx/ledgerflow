# Builds CODA files (Febelfin, fixed-width 128-character records) for the specs of F02, because real bank files are
# not available. Fictitious banks, holders, counterparties and IBANs (valid check digits, no real account).
#
# The layout follows the public Febelfin CODA specification as understood by the author, record by record (types 0, 1,
# 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 4, 8, 9). It tests the parser against the specification, NOT against the habits of each
# bank: when real files are at hand, they must be added next to these and checked against them.
#
#   CodaBuilder.file(statements: [ { iban: CodaBuilder.iban("539007547034"), movements: [ { amount: "100.00", ... } ] } ])
module CodaBuilder
  RECORD_LENGTH = 128

  # A Belgian IBAN from the 12 digits of a BBAN (check digits are recomputed so the result is valid).
  def self.iban(bban)
    bban = bban.to_s
    base = bban[0, 10]
    check = base.to_i % 97
    bban = "#{base}#{format('%02d', check.zero? ? 97 : check)}"
    remainder = 98 - "#{bban}111400".to_i % 97
    "BE#{format('%02d', remainder)}#{bban}"
  end

  # +++123/4567/89002+++ digits (12), valid unless `valid: false`.
  def self.structured(id, valid: true)
    digits = Accounting::StructuredCommunication.for_id(id)
    valid ? digits : "#{digits[0, 10]}#{format('%02d', (digits[10, 2].to_i + 1) % 100)}"
  end

  def self.amount15(value) = format("%015d", (BigDecimal(value.to_s).abs * 1000).round.to_i)
  def self.date6(date) = date.strftime("%d%m%y")
  def self.sign(value) = BigDecimal(value.to_s).negative? ? "1" : "0"

  # Fixed width: the value cut or padded with spaces to `width`.
  def self.pad(value, width) = value.to_s.ljust(width)[0, width]

  # statements: [{ iban:, currency: "EUR", holder:, description:, sequence:, date:, old_balance:, new_balance: (computed),
  #                movements: [{ amount:, value_date:, entry_date:, bank_reference:, structured:, free:, counterparty_name:,
  #                              counterparty_iban:, counterparty_bic:, code:, customer_reference:, message:, information: [] }] }]
  # raw: lines appended or replaced by the caller (to break the file on purpose). Returns the text, lines ending in CRLF.
  def self.file(statements:, created: Date.new(2026, 3, 31), bank: "539", holder_name: "ACME SRL", encoding: nil, trailer: true)
    lines = [ header(created, bank, holder_name) ]
    debit = BigDecimal("0")
    credit = BigDecimal("0")
    statements.each_with_index do |statement, index|
      statement = defaults(statement, index, created)
      lines << old_balance(statement)
      movements = statement.fetch(:movements)
      movements.each_with_index do |movement, i|
        lines.concat(movement_records(movement, i + 1, statement))
        amount = BigDecimal(movement.fetch(:amount).to_s)
        amount.negative? ? debit += amount.abs : credit += amount
      end
      lines << new_balance(statement)
    end
    lines << trailer_record(lines.count { |l| l[0].between?("1", "8") }, debit, credit) if trailer
    text = lines.map { |l| "#{l}\r\n" }.join
    encoding ? text.encode(encoding) : text
  end

  def self.defaults(statement, index, created)
    statement = { iban: iban("539007547034"), currency: "EUR", holder: "ACME SRL", description: "COMPTE COURANT", sequence: index + 1,
                  date: created, old_balance: "0.00", movements: [] }.merge(statement)
    statement[:new_balance] ||= (BigDecimal(statement[:old_balance].to_s) + statement[:movements].sum { |m| BigDecimal(m[:amount].to_s) }).to_s("F")
    statement
  end

  def self.header(created, bank, name)
    "0" + "0000" + date6(created) + pad(bank, 3) + "05" + " " + " " * 7 + pad("0000000001", 10) + pad(name, 26) +
      pad("GEBABEBB", 11) + pad("0123456789", 11) + " " + " " * 5 + pad("", 16) + pad("", 16) + " " * 7 + "2"
  end

  def self.account37(statement) = pad(statement[:iban], 34) + pad(statement[:currency], 3)

  def self.old_balance(statement)
    balance = statement[:old_balance]
    "1" + "2" + format("%03d", statement[:sequence]) + account37(statement) + sign(balance) + amount15(balance) +
      date6(statement[:date] - 1) + pad(statement[:holder], 26) + pad(statement[:description], 35) + format("%03d", statement[:sequence])
  end

  def self.new_balance(statement)
    balance = statement[:new_balance]
    "8" + format("%03d", statement[:sequence]) + account37(statement) + sign(balance) + amount15(balance) +
      date6(statement[:date]) + " " * 64 + "0"
  end

  def self.trailer_record(count, debit, credit)
    "9" + " " * 15 + format("%06d", count) + amount15(debit) + amount15(credit) + " " * 75 + "2"
  end

  # 2.1 always; 2.2 and 2.3 when the movement carries a customer reference / counterparty; 3.x for the extra information; 4 for a message.
  def self.movement_records(movement, number, statement)
    seq = format("%04d", number)
    value_date = movement[:value_date] || statement[:date]
    entry_date = movement[:entry_date] || value_date
    structured = movement[:structured]
    communication = structured ? "101#{structured}" : movement[:free].to_s
    has22 = movement[:customer_reference].present? || movement[:counterparty_bic].present? || movement[:free_long].present?
    has23 = movement[:counterparty_iban].present? || movement[:counterparty_name].present?
    information = Array(movement[:information])
    more = ->(*flags) { flags.any? ? "1" : "0" }

    records = []
    records << "2" + "1" + seq + "0000" + pad(movement[:bank_reference] || "REF#{number}", 21) + sign(movement[:amount]) + amount15(movement[:amount]) +
               date6(value_date) + pad(movement[:code] || "04010000", 8) + (structured ? "1" : "0") + pad(communication, 53) + date6(entry_date) +
               format("%03d", statement[:sequence]) + "0" + more.(has22 || has23) + " " + more.(information.any? || movement[:message].present?)
    if has22
      records << "2" + "2" + seq + "0000" + pad(movement[:free_long], 53) + pad(movement[:customer_reference], 35) + pad(movement[:counterparty_bic], 11) +
                 " " * 2 + " " + " " * 4 + " " * 5 + " " * 4 + more.(has23) + " " + more.(information.any? || movement[:message].present?)
    end
    if has23
      records << "2" + "3" + seq + "0000" + pad(pad(movement[:counterparty_iban], 34) + movement[:counterparty_currency].to_s, 37) +
                 pad(movement[:counterparty_name], 35) + pad(movement[:counterparty_text], 43) + "0" + " " + more.(information.any? || movement[:message].present?)
    end
    information.each_with_index do |text, i|
      last = i == information.size - 1 && movement[:message].blank?
      records << "3" + "1" + seq + format("%04d", i + 1) + pad(movement[:bank_reference] || "REF#{number}", 21) + pad(movement[:code] || "04010000", 8) +
                 "0" + pad(text, 73) + " " * 12 + "0" + " " + (last ? "0" : "1")
    end
    records << "4" + " " + seq + "0000" + pad(movement[:message], 105) + " " * 12 + "0" if movement[:message].present?
    records
  end
end
