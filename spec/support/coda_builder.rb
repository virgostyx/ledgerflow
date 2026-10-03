# Builds CODA files (Febelfin, fixed-width 128-character records) for the specs of F02, because real bank files are
# not available. Fictitious banks, holders, counterparties and IBANs (valid check digits, no real account).
#
# The layout follows the Febelfin CODA specification v2.8 (docs/dev/features/standard-coda-fr_-2025.pdf, annex I), record
# by record (types 0, 1, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 4, 8, 9). It tests the parser against the specification, NOT against the habits of each
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

  # type 0, family 01 (SEPA credit transfers), operation 50 (in your favour) or 01 (simple transfer), rubric 000 (annex II)
  def self.default_code(movement) = BigDecimal(movement[:amount].to_s).negative? ? "00101000" : "00150000"

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
    statements = statements.each_with_index.map { |statement, index| defaults(statement, index, created) }
    lines = statements.each_with_index.flat_map do |statement, index|
      logical_file(statement, created, bank, holder_name, last: index == statements.size - 1, trailer: trailer)
    end
    text = lines.map { |l| "#{l}\r\n" }.join
    encoding ? text.encode(encoding) : text
  end

  # One account = one logical file: 0, 1, the movements, 8 (absent from an empty file, spec §2), the free messages (4,
  # only between 8 and 9), 9. The physical file holds several of them, the last trailer saying so (code 2, else 1).
  def self.logical_file(statement, created, bank, holder_name, last:, trailer:)
    movements = statement.fetch(:movements)
    messages = Array(statement[:messages])
    empty = movements.empty? && messages.empty? && statement[:empty] != false
    lines = [ header(created, bank, holder_name), old_balance(statement) ]
    movements.each_with_index { |movement, i| lines.concat(movement_records(movement, i + 1, statement)) }
    lines << new_balance(statement, messages.any?) unless empty
    messages.each_with_index { |text, i| lines << free_message(text, i + 1, last: i == messages.size - 1) }
    debit = movements.sum(BigDecimal("0")) { |m| BigDecimal(m[:amount].to_s).negative? ? BigDecimal(m[:amount].to_s).abs : 0 }
    credit = movements.sum(BigDecimal("0")) { |m| BigDecimal(m[:amount].to_s).positive? ? BigDecimal(m[:amount].to_s) : 0 }
    # the trailer counts the records 1, 2.x, 3.x and 8 (not 0, 4 nor 9), the totals the movements (2.1, detail 0000)
    lines << trailer_record(lines.count { |l| l[0].between?("1", "3") || l[0] == "8" }, debit, credit, last: last) if trailer
    lines
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

  def self.new_balance(statement, messages_follow)
    balance = statement[:new_balance]
    "8" + format("%03d", statement[:sequence]) + account37(statement) + sign(balance) + amount15(balance) +
      date6(statement[:date]) + " " * 64 + (messages_follow ? "1" : "0")
  end

  # Record 4, free message (spec, annex I): 3-6 sequence, 7-10 detail, 11-32 blank, 33-112 text (80), 113-127 blank, 128 link.
  def self.free_message(text, number, last:)
    "4" + " " + format("%04d", number) + "0000" + " " * 22 + pad(text, 80) + " " * 15 + (last ? "0" : "1")
  end

  def self.trailer_record(count, debit, credit, last: true)
    "9" + " " * 15 + format("%06d", count) + amount15(debit) + amount15(credit) + " " * 75 + (last ? "2" : "1")
  end

  # 2.1 always; 2.2 and 2.3 when the movement carries a customer reference / counterparty; 3.x for the extra information; 4 for a message.
  def self.movement_records(movement, number, statement)
    seq = format("%04d", number)
    value_date = movement[:value_date] || statement[:date]
    entry_date = movement[:entry_date] || value_date
    structured = movement[:structured]
    communication = structured ? "#{movement[:structured_type] || "101"}#{structured}" : movement[:free].to_s
    has22 = movement[:customer_reference].present? || movement[:counterparty_bic].present? || movement[:free_long].present?
    has23 = movement[:counterparty_iban].present? || movement[:counterparty_name].present?
    information = Array(movement[:information])
    more = ->(*flags) { flags.any? ? "1" : "0" }

    records = []
    records << "2" + "1" + seq + "0000" + pad(movement[:bank_reference] || "REF#{number}", 21) + sign(movement[:amount]) + amount15(movement[:amount]) +
               date6(value_date) + pad(movement[:code] || default_code(movement), 8) + (structured ? "1" : "0") + pad(communication, 53) + date6(entry_date) +
               format("%03d", statement[:sequence]) + "0" + more.(has22 || has23) + " " + more.(information.any?)
    if has22
      records << "2" + "2" + seq + "0000" + pad(movement[:free_long], 53) + pad(movement[:customer_reference], 35) + pad(movement[:counterparty_bic], 11) +
                 " " * 3 + pad(movement[:r_type], 1) + pad(movement[:iso_reason], 4) + pad(movement[:category_purpose], 4) + pad(movement[:purpose], 4) + more.(has23) + " " + more.(information.any?)
    end
    if has23
      records << "2" + "3" + seq + "0000" + pad(pad(movement[:counterparty_iban], 34) + movement[:counterparty_currency].to_s, 37) +
                 pad(movement[:counterparty_name], 35) + pad(movement[:counterparty_text], 43) + "0" + " " + more.(information.any?)
    end
    information.each_with_index do |text, i|
      last = i == information.size - 1
      records << "3" + "1" + seq + format("%04d", i + 1) + pad(movement[:bank_reference] || "REF#{number}", 21) + pad(movement[:code] || default_code(movement), 8) +
                 "0" + pad(text, 73) + " " * 12 + "0" + " " + (last ? "0" : "1")
    end
    records
  end
end
