require "csv"

# First-time migration from another accounting system, at the start of the entity's first fiscal year:
# a balance sheet (classes 1-5) and the open customer/supplier invoices. All or nothing.
#
# Each open invoice gets its own posted entry (D 400000 / C 499000, or D 499000 / C 440000) and a posted
# Invoice without lines, so that lettering, bank matching, reminders and the aged balance work on it (they
# find the trade line by journal entry). One more entry carries the other accounts and clears the 499000
# suspense account. Amounts are EUR only.
class Accounting::ImportOpeningBalances
  TRADE = { "customer" => Accounting::AccountCodes::CUSTOMERS, "supplier" => Accounting::AccountCodes::SUPPLIERS }.freeze

  def self.call(fiscal_year:, balances_csv:, invoices_csv:, dry_run: false)
    new(fiscal_year, balances_csv, invoices_csv, dry_run).call
  end

  def initialize(fiscal_year, balances_csv, invoices_csv, dry_run)
    @fiscal_year = fiscal_year
    @balances_csv = balances_csv
    @invoices_csv = invoices_csv
    @dry_run = dry_run
    @errors = []
    @partners = {}
    @partners_created = 0
  end

  def call
    check_fiscal_year
    @journal = Accounting::Journal.active.find_by(journal_type: :misc)
    @errors << "No active misc journal to book the opening entries" unless @journal
    @balances = parse_balances
    @invoices = parse_invoices
    check_totals

    return refuse if @errors.any?

    summary = nil
    ApplicationRecord.transaction do
      summary = import
      raise ActiveRecord::Rollback if @dry_run
    end
    LightService::Context.make(errors: [], summary: summary)
  end

  private

  def refuse
    ctx = LightService::Context.make(errors: @errors, summary: {})
    ctx.fail!("Import refused: #{@errors.size} error(s)")
    ctx
  end

  def check_fiscal_year
    @errors << "The fiscal year must be open" unless @fiscal_year.open?
    if Accounting::FiscalYear.where("start_date < ?", @fiscal_year.start_date).exists?
      @errors << "Opening balances can only be imported into the first fiscal year of the entity"
    end
    if Accounting::JournalEntry.where(fiscal_year: @fiscal_year, source_type: Accounting::JournalEntry::OPENING_SOURCE).exists?
      @errors << "The opening balances were already imported into this fiscal year"
    end
  end

  # => { Account => net debit }, zero balances dropped
  def parse_balances
    net = Hash.new(BigDecimal("0"))
    rows(@balances_csv, "Balances").each do |line, row|
      account = Accounting::Account.find_by(code: row["account_code"].to_s.strip)
      debit, credit = amount(row["debit"]), amount(row["credit"])
      if account.nil?
        @errors << "Balances line #{line}: account #{row['account_code']} is unknown"
      elsif !(1..5).cover?(account.account_class)
        @errors << "Balances line #{line}: account #{account.code} must be in class 1 to 5"
      elsif debit.nil? || credit.nil? || debit.negative? || credit.negative?
        @errors << "Balances line #{line}: debit and credit must be amounts of zero or more"
      else
        net[account] += debit - credit
      end
    end
    debit  = net.values.select(&:positive?).sum(BigDecimal("0"))
    credit = -net.values.select(&:negative?).sum(BigDecimal("0"))
    @errors << "Balances are not balanced: debit #{debit.to_s('F')}, credit #{credit.to_s('F')}" if debit != credit
    net.reject { |_, v| v.zero? }
  end

  def parse_invoices
    seen = Set.new
    rows(@invoices_csv, "Invoices").filter_map do |line, row|
      type = row["type"].to_s.strip.downcase
      number = row["number"].to_s.strip
      inv_date = date(row["invoice_date"])
      due_date = row["due_date"].to_s.strip.empty? ? nil : date(row["due_date"])
      open_amount = amount(row["open_amount"])
      vat = row["partner_vat"].to_s.strip.upcase.delete(" ")
      name = row["partner_name"].to_s.strip

      problem =
        if TRADE.keys.exclude?(type) then "type must be customer or supplier"
        elsif name.empty? && vat.empty? then "partner_name or partner_vat is required"
        elsif vat.present? && !Accounting::Partner.valid_vat_number?(vat) then "partner_vat #{vat} is not a valid VAT number"
        elsif number.empty? then "number is required"
        elsif !seen.add?(number) then "duplicate number #{number}"
        elsif Accounting::Invoice.exists?(invoice_number: number) then "invoice number #{number} already exists"
        elsif inv_date.nil? then "invoice_date is not a valid date (YYYY-MM-DD)"
        elsif row["due_date"].to_s.strip.present? && due_date.nil? then "due_date is not a valid date (YYYY-MM-DD)"
        elsif open_amount.nil? || !open_amount.positive? then "open_amount must be greater than 0"
        end
      (@errors << "Invoices line #{line}: #{problem}"; next) if problem

      { type:, number:, name:, vat: vat.presence, invoice_date: inv_date, due_date:, amount: open_amount }
    end
  end

  # The trade accounts must equal the open invoices, since the invoices are what fills them.
  def check_totals
    TRADE.each do |type, code|
      account = Accounting::Account.find_by(code:)
      expected = (@balances[account] || 0) * (type == "customer" ? 1 : -1)
      total = @invoices.select { |i| i[:type] == type }.sum(BigDecimal("0")) { |i| i[:amount] }
      next if expected == total

      @errors << "Account #{code}: balance #{expected.to_d.to_s('F')} does not match the #{type} invoices total #{total.to_s('F')}"
    end
  end

  def import
    @invoices.each { |i| import_invoice(i) }
    balance_entry
    { invoices: @invoices.size, partners_created: @partners_created, balance_accounts: others.size }
  end

  def others
    @balances.reject { |account, _| TRADE.value?(account.code) }
  end

  def import_invoice(data)
    partner = partner_for(data)
    invoice = Accounting::Invoice.create!(
      invoice_type: data[:type], partner:, fiscal_year: @fiscal_year, invoice_date: data[:invoice_date],
      due_date: data[:due_date], invoice_number: data[:number], external_ref: data[:number], currency: "EUR",
      exchange_rate: 1, subtotal_excl_vat: data[:amount], vat_amount: 0, total_incl_vat: data[:amount], status: :posted
    )
    trade = Accounting::Account.find_by!(code: TRADE.fetch(data[:type]))
    transit = Accounting::Account.find_by!(code: Accounting::AccountCodes::TRANSIT)
    customer = data[:type] == "customer"
    entry = post_entry("Opening balance — invoice #{data[:number]} (#{partner.name})", [
      [ trade, customer ? data[:amount] : 0, customer ? 0 : data[:amount], { partner:, invoice: } ],
      [ transit, customer ? 0 : data[:amount], customer ? data[:amount] : 0, {} ]
    ])
    invoice.update!(journal_entry: entry)
  end

  def balance_entry
    lines = others.map { |account, net| [ account, [ net, 0 ].max, [ -net, 0 ].max, {} ] }
    diff = others.values.sum(BigDecimal("0")) # what the transit account must offset
    transit = Accounting::Account.find_by!(code: Accounting::AccountCodes::TRANSIT)
    lines << [ transit, [ -diff, 0 ].max, [ diff, 0 ].max, {} ] unless diff.zero?
    post_entry("Opening balance", lines) if lines.any?
  end

  def post_entry(description, lines)
    entry = Accounting::JournalEntry.new(
      journal: @journal, fiscal_year: @fiscal_year, entry_date: @fiscal_year.start_date, description:,
      status: :draft, source_type: Accounting::JournalEntry::OPENING_SOURCE
    )
    entry.reference = @journal.next_sequence_number(year: @fiscal_year.start_date.year)
    entry.save!
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    lines.each do |account, debit, credit, extra|
      Accounting::JournalEntryLine.create!(journal_entry: entry, account:, debit:, credit:, label: "Opening balance", **extra)
    end
    entry.post!
    entry
  end

  # Matched by VAT number, then by name (case-insensitive); created when missing.
  def partner_for(data)
    key = data[:vat] || data[:name].downcase
    partner = @partners[key] ||= find_partner(data) || create_partner(data)
    partner.update!(partner_type: :both) if partner.partner_type != data[:type] && !partner.both?
    partner
  end

  def find_partner(data)
    (data[:vat] && Accounting::Partner.find_by(vat_number: data[:vat])) ||
      Accounting::Partner.where("LOWER(name) = ?", data[:name].downcase).first
  end

  def create_partner(data)
    @partners_created += 1
    Accounting::Partner.create!(name: data[:name].presence || data[:vat], vat_number: data[:vat], partner_type: data[:type])
  end

  # => [[line_number, row], ...]; the header is line 1
  def rows(text, label)
    text = text.to_s.strip
    sep = text.lines.first.to_s.include?(";") ? ";" : ","
    table = CSV.parse(text, headers: true, col_sep: sep, skip_blanks: true, header_converters: ->(h) { h.to_s.strip.downcase })
    table.each_with_index.map { |row, i| [ i + 2, row ] }
  rescue CSV::MalformedCSVError => e
    @errors << "#{label}: unreadable CSV (#{e.message})"
    []
  end

  # "1.234,56", "1234.56" or "1 234,56"; nil when it is not a number
  def amount(text)
    s = text.to_s.strip.delete(" ")
    return BigDecimal("0") if s.empty?

    BigDecimal(s.include?(",") ? s.delete(".").tr(",", ".") : s)
  rescue ArgumentError
    nil
  end

  def date(text)
    s = text.to_s.strip
    Date.iso8601(s)
  rescue Date::Error
    begin
      Date.strptime(s, "%d/%m/%Y")
    rescue Date::Error
      nil
    end
  end
end
