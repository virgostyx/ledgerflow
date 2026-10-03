# Reads a CODA file (Febelfin standard v2.8, docs/dev/features/standard-coda-fr_-2025.pdf, annex I) into statements.
# Pure: bytes (or text) in, Banking::ParseResult out. A structural fault anywhere refuses the file whole, with every faulty
# line; a statement that does not add up, a wrong structured communication, a trailer total that differs are flagged, not refused.
#
# One logical file (records 0 ... 9) per account; a physical file holds several. Each account block (1 ... 8) is a statement.
class Banking::Coda::Parser
  include Banking::StatementParser

  RECORD_LENGTH = 128
  # What may follow what (spec §2, §5.5, §5.6, annex I). 21/22/23 = records 2.1 to 2.3, 31/32/33 = 3.1 to 3.3.
  FOLLOWERS = {
    start: %w[0], "0" => %w[1], "1" => %w[21 8 9], "21" => %w[21 22 23 31 8], "22" => %w[21 23 31 8], "23" => %w[21 31 8],
    "31" => %w[21 31 32 8], "32" => %w[21 31 33 8], "33" => %w[21 31 8], "8" => %w[1 4 9], "4" => %w[4 9], "9" => %w[0]
  }.freeze

  def call(input, encoding: nil)
    @errors = []
    @warnings = []
    records = split(decode(input, encoding))
    return failure("the file is empty") if records.empty?

    check_formats(records)
    check_order(records)
    statements = @errors.empty? ? build(records) : []
    Banking::ParseResult.new(statements: statements, errors: @errors.sort_by(&:line), warnings: @warnings)
  end

  private

  def failure(text)
    Banking::ParseResult.new(statements: [], errors: [ Banking::ParseError.new(line: 1, text: text) ], warnings: [])
  end

  def error(line, text) = @errors << Banking::ParseError.new(line: line, text: text)

  # --- reading the bytes -------------------------------------------------------------------------------------------

  # Banks send ISO-8859-1 or CP850 (spec: any single-byte set); UTF-8 is taken when it is valid UTF-8. Bytes 0x80-0x9F are
  # accented letters in CP850 and control characters in ISO-8859-1: their presence tells CP850.
  def decode(input, encoding)
    bytes = input.to_s.b.sub(/\x1A+\z/n, "")
    name = encoding || detect_encoding(bytes)
    bytes.force_encoding(name).encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
  end

  def detect_encoding(bytes)
    return "UTF-8" if bytes.dup.force_encoding("UTF-8").then { |text| text.valid_encoding? && !text.ascii_only? }
    return "CP850" if bytes.match?(/[\x80-\x9F]/n)

    "ISO-8859-1"
  end

  # Records of 128 characters, one per line (CRLF, LF or CR) or, without line ends, one every 128 characters. [[line, text], ...]
  def split(text)
    lines = text.split(/\r\n|\n|\r/)
    lines.pop while lines.any? && lines.last.strip.empty?
    lines = lines.first.scan(/.{1,#{RECORD_LENGTH}}/m) if lines.size == 1 && lines.first.length > RECORD_LENGTH && (lines.first.length % RECORD_LENGTH).zero?
    lines.each_with_index.map { |record, index| [ index + 1, record ] }
  end

  # --- structure ---------------------------------------------------------------------------------------------------

  def key(record)
    type = record[0]
    %w[2 3].include?(type) ? "#{type}#{record[1]}" : type
  end

  def check_formats(records)
    records.each do |line, record|
      next error(line, "#{record.length} characters instead of #{RECORD_LENGTH}") unless record.length == RECORD_LENGTH
      next error(line, %(unknown record type "#{record[0]}")) unless %w[0 1 2 3 4 8 9].include?(record[0])
      next error(line, %(unknown article code "#{record[1]}" for record type #{record[0]})) unless FOLLOWERS.key?(key(record))

      check_fields(line, record)
    end
  end

  def check_fields(line, record)
    case key(record)
    when "0" then date(line, record, 6, 11, "creation date")
    when "1"
      error(line, %(unknown account structure "#{record[1]}")) unless %w[0 1 2 3].include?(record[1])
      sign(line, record, 43)
      number(line, record, 44, 58, "old balance")
      date(line, record, 59, 64, "old balance date")
    when "21"
      sign(line, record, 32)
      number(line, record, 33, 47, "amount")
      date(line, record, 48, 53, "value date", allow_zero: true)
      date(line, record, 116, 121, "entry date")
    when "8"
      sign(line, record, 42)
      number(line, record, 43, 57, "new balance")
      date(line, record, 58, 63, "new balance date")
    when "9"
      number(line, record, 17, 22, "record count")
    end
  end

  def check_order(records)
    previous = :start
    records.each do |line, record|
      current = key(record)
      next unless FOLLOWERS.key?(current)

      error(line, "record #{label(current)} cannot #{previous == :start ? 'start the file' : "follow record #{label(previous)}"}") unless FOLLOWERS.fetch(previous).include?(current)
      previous = current
    end
    last_line, last = records.last
    error(last_line, "the file ends without a trailer (record 9)") unless key(last) == "9"
  end

  def label(key) = key.length == 2 ? "#{key[0]}.#{key[1]}" : key

  def sign(line, record, at)
    error(line, %(unknown sign "#{record[at - 1]}" (0 = credit, 1 = debit))) unless %w[0 1].include?(record[at - 1])
  end

  def number(line, record, from, to, name)
    error(line, "#{name} is not a number: #{record[from - 1, to - from + 1].inspect}") unless record[from - 1, to - from + 1].match?(/\A\d+\z/)
  end

  def date(line, record, from, to, name, allow_zero: false)
    text = record[from - 1, to - from + 1]
    return if allow_zero && text == "000000"

    error(line, "#{name} is not a date: #{text.inspect}") unless parse_date(text)
  end

  def parse_date(text)
    return unless text.match?(/\A\d{6}\z/)

    Date.new(2000 + text[4, 2].to_i, text[2, 2].to_i, text[0, 2].to_i)
  rescue Date::Error
    nil
  end

  # --- building the statements -------------------------------------------------------------------------------------

  def f(record, from, to = from) = record[from - 1, to - from + 1]
  def amount(record, sign_at, from, to) = BigDecimal(f(record, from, to)) / 1000 * (f(record, sign_at) == "1" ? -1 : 1)
  def money_date(record, from, to) = f(record, from, to) == "000000" ? nil : parse_date(f(record, from, to))

  def build(records)
    statements = []
    header = block = movement = nil
    file_start = count = 0
    records.each do |line, record|
      case key(record)
      when "0"
        header = read_header(record)
        file_start = statements.size
        count = 0
      when "1"
        statements << (block = read_old_balance(record, header))
      when "21" then movement = read_movement(record, block)
      when "22" then read_movement_part2(record, movement)
      when "23" then read_movement_part3(record, movement)
      when "31", "32", "33" then read_information(record, movement)
      when "8" then read_new_balance(record, block)
      when "4" then block.messages << f(record, 33, 112).strip
      when "9" then check_trailer(record, line, statements[file_start..], count)
      end
      count += 1 if %w[1 21 22 23 31 32 33 8].include?(key(record))
    end
    statements.each do |statement|
      statement.lines.each do |l|
        (l.details + [ l ]).each { |part| part.communication = part.communication.squeeze(" ").strip }
        l.fingerprint = fingerprint(statement, l)
      end
    end
    statements
  end

  def read_header(record)
    { created_on: parse_date(f(record, 6, 11)), bank_id: f(record, 12, 14), duplicate: f(record, 17) == "D", file_reference: f(record, 25, 34).strip,
      addressee: f(record, 35, 60).strip, bic: f(record, 61, 71).strip, company_id: f(record, 72, 82).strip }
  end

  def read_old_balance(record, header)
    structure = f(record, 2)
    account, currency = account_and_currency(structure, f(record, 6, 42))
    Banking::ParsedStatement.new(
      iban: account[:iban], account_number: account[:number], currency: currency, account_structure: structure.to_i,
      holder: f(record, 65, 90).strip, description: f(record, 91, 125).strip, sequence: f(record, 126, 128).to_i,
      old_balance: amount(record, 43, 44, 58), old_balance_date: parse_date(f(record, 59, 64)),
      lines: [], messages: [], header: header, addressee: header[:addressee]
    )
  end

  # Spec §7.5: structure 0 = Belgian BBAN (12 digits, blank, currency), 1 = foreign BBAN, 2 = Belgian IBAN, 3 = foreign IBAN.
  def account_and_currency(structure, field)
    case structure
    when "0"
      number = field[0, 12]
      [ { number: number, iban: Banking::Iban.from_belgian_bban(number) }, field[13, 3].to_s.strip.presence ]
    when "1" then [ { number: field[0, 34].strip, iban: nil }, field[34, 3].to_s.strip.presence ]
    else
      iban = field[0, 34].strip
      [ { number: iban, iban: iban }, field[34, 3].to_s.strip.presence ]
    end
  end

  def read_movement(record, statement)
    comm_type = f(record, 62)
    comm = f(record, 63, 115)
    movement = Banking::ParsedLine.new(
      sequence: f(record, 3, 6).to_i, detail: f(record, 7, 10).to_i, bank_reference: f(record, 11, 31).strip, amount: amount(record, 32, 33, 47),
      value_date: money_date(record, 48, 53), entry_date: parse_date(f(record, 116, 121)),
      transaction: { type: f(record, 54), family: f(record, 55, 56), operation: f(record, 57, 58), rubric: f(record, 59, 61) },
      communication: comm_type == "0" ? comm : "", information: [], raw: [ record ], details: []
    )
    structured(movement, comm) if comm_type == "1"
    parent = statement.lines.reverse.find { |l| l.sequence == movement.sequence && l.detail.zero? }
    if movement.detail.positive? && parent
      parent.details << movement
    else
      statement.lines << movement
    end
    movement
  end

  # Spec annex III: 100 = ISO 11649 creditor reference, 101/102 = Belgian structured communication (12 digits, modulo 97).
  def structured(movement, comm)
    movement.structured_type = comm[0, 3]
    payload = comm[3..]
    case movement.structured_type
    when "101", "102"
      movement.structured_communication = payload[0, 12]
      movement.structured_valid = Accounting::StructuredCommunication.valid?(movement.structured_communication)
    when "100"
      movement.structured_communication = payload.strip
      movement.structured_valid = Banking::Iban.valid_creditor_reference?(movement.structured_communication)
    else
      movement.communication = comm.strip
    end
  end

  def read_movement_part2(record, movement)
    movement.raw << record
    movement.communication += f(record, 11, 63) unless movement.structured_type
    movement.customer_reference = f(record, 64, 98).strip.presence
    movement.counterparty_bic = f(record, 99, 109).strip.presence
    movement.r_type = f(record, 113).strip.presence
    movement.iso_reason = f(record, 114, 117).strip.presence
    movement.category_purpose = f(record, 118, 121).strip.presence
    movement.purpose = f(record, 122, 125).strip.presence
  end

  def read_movement_part3(record, movement)
    movement.raw << record
    account = f(record, 11, 44).strip
    movement.counterparty_account = account.presence
    movement.counterparty_iban = account if Banking::Iban.valid?(account)
    movement.counterparty_iban ||= Banking::Iban.from_belgian_bban(account) if account.match?(/\A\d{12}\z/)
    movement.counterparty_currency = f(record, 45, 47).strip.presence
    movement.counterparty_name = f(record, 48, 82).strip.presence
    movement.counterparty_text = f(record, 83, 125).strip.presence
    movement.communication += " #{f(record, 83, 125)}" unless movement.structured_type
  end

  def read_information(record, movement)
    movement.raw << record
    case f(record, 2)
    when "1" then movement.information << f(record, 41, 113).strip
    when "2" then movement.information[-1] = "#{movement.information.last}#{f(record, 11, 115).strip}"
    when "3" then movement.information[-1] = "#{movement.information.last}#{f(record, 11, 100).strip}"
    end
  end

  def read_new_balance(record, statement)
    statement.new_balance = amount(record, 42, 43, 57)
    statement.new_balance_date = parse_date(f(record, 58, 63))
  end

  # The count refuses the file (a truncated or altered file); the turnover only warns (spec annex I: type 2 records, detail 0000).
  def check_trailer(record, line, statements, count)
    counted = f(record, 17, 22).to_i
    error(line, "the trailer counts #{counted} records, the file holds #{count}") unless counted == count

    lines = statements.flat_map(&:lines)
    debit  = lines.select(&:debit?).sum(BigDecimal("0")) { |l| l.amount.abs }
    credit = lines.select(&:credit?).sum(BigDecimal("0"), &:amount)
    @warnings << "line #{line}: the trailer totals #{BigDecimal(f(record, 23, 37)) / 1000} debit and #{BigDecimal(f(record, 38, 52)) / 1000} credit, the movements #{debit} and #{credit}" unless
      BigDecimal(f(record, 23, 37)) / 1000 == debit && BigDecimal(f(record, 38, 52)) / 1000 == credit
  end

  # What identifies a movement across files (spec F02, idempotence): account, dates, signed amount, bank reference, counterparty,
  # communication. Not its sequence number, which changes from one statement to the next.
  def fingerprint(statement, line)
    Digest::SHA256.hexdigest([ statement.iban || statement.account_number, line.entry_date&.iso8601, line.value_date&.iso8601, line.amount.to_s("F"), line.bank_reference,
                               line.counterparty_iban || line.counterparty_name, line.structured_communication || line.communication ].join("|"))
  end
end
