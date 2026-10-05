# F13a: entries in batches (a payroll journal, the sales of a shop, the entries of another tool). The lines of a file are gathered into pieces
# by the piece number; a piece that does not balance, or that cannot be placed, is refused as a whole and does not stop the others. Pieces
# are created as drafts, never validated here. The piece number is kept as the `external_id` of the entry: a piece already there is skipped.
class Imports::Kinds::Entries < Imports::Kind
  FIELDS = { "piece" => true, "date" => true, "journal" => true, "account" => true, "debit" => false, "credit" => false,
             "label" => false, "description" => false, "partner" => false }.freeze
  Piece = Struct.new(:key, :date, :journal, :fiscal_year, :description, :lines, keyword_init: true)
  PieceLine = Struct.new(:account, :debit, :credit, :label, :partner, keyword_init: true) # partner: a Partner or the name to create

  def analyze
    analysis = Imports::Analysis.blank
    analysis.read = @table.rows.size
    return analysis unless check_mapping!(analysis)

    analysis.refuse(nil, [], "Map a column to debit or credit") unless mapped?("debit") || mapped?("credit")
    return analysis if analysis.errors.any?

    load_references
    pieces = @table.rows.each_with_index.group_by { |row, _| cell(row, "piece") }
    pieces.each do |key, rows|
      lines = rows.map { |_, i| @table.lines[i] }
      next analysis.refuse(nil, lines, "A line has no piece number") if key.nil?

      if @existing_keys.include?(key)
        analysis.skipped << { ref: key, message: "already imported" }
      elsif (problem = build(key, rows, analysis))
        analysis.refuse(key, lines, problem)
      else
        analysis.items << @built
      end
    end
    analysis
  end

  def self.write(items, batch:, user:)
    created = 0
    refused = []
    partners = {}
    items.each do |piece|
      ApplicationRecord.transaction(requires_new: true) do
        ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
        entry = Accounting::JournalEntry.create!(journal: piece.journal, fiscal_year: piece.fiscal_year, entry_date: piece.date, status: :draft,
                                                 description: piece.description, created_by: user, external_id: piece.key, import_batch_id: batch.id)
        piece.lines.each_with_index do |line, i|
          partner = line.partner.is_a?(String) ? (partners[line.partner] ||= created_partner(line.partner, batch)) : line.partner
          entry.lines.create!(account: line.account, debit: line.debit, credit: line.credit, label: line.label, partner: partner, sort_order: i)
        end
        created += 1
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      refused << { ref: piece.key, lines: [], message: e.message }
    end
    { created: created, refused: refused }
  end

  def self.created_partner(name, batch)
    Accounting::Partner.find_by("lower(name) = ?", name.downcase) ||
      Accounting::Partner.create!(name: name, partner_type: :both, to_validate: true, import_batch_id: batch.id)
  end

  private

  def load_references
    @accounts    = Accounting::Account.all.index_by(&:code)
    @journals    = Accounting::Journal.active.index_by(&:code)
    @partners    = Accounting::Partner.all
    @years       = Accounting::FiscalYear.open_years.to_a
    @existing_keys = Accounting::JournalEntry.where.not(external_id: nil).pluck(:external_id).to_set
    @lock_by_date  = Hash.new { |h, date| h[date] = Accounting::PeriodLock.covering(date).first }
  end

  # => nil and @built when the piece can be written, else the reason it is refused
  def build(key, rows, analysis)
    problems = []
    cells = ->(field) { rows.map { |row, _| cell(row, field) }.uniq }
    date = single(cells.("date"), "date", problems) { |v| parse_date(v) }
    journal_code = single(cells.("journal"), "journal", problems)
    journal = journal_code && @journals[journal_code]
    problems << "journal #{journal_code} is unknown" if journal_code && !journal
    year = date && @years.find { |y| y.start_date <= date && y.end_date >= date }
    problems << "there is no open fiscal year at #{date}" if date && !year
    if date && (lock = @lock_by_date[date])
      problems << I18n.t("accounting.errors.period_locked", starts_on: lock.starts_on, ends_on: lock.ends_on)
    end

    lines = rows.filter_map { |row, i| line(row, @table.lines[i], analysis, problems) }
    problems << "a piece needs at least two lines" if rows.size < 2
    if lines.size == rows.size && problems.empty?
      debit, credit = lines.sum(&:debit), lines.sum(&:credit)
      problems << "the piece does not balance: debit #{format('%.2f', debit)}, credit #{format('%.2f', credit)}" unless debit == credit
    end
    return problems.uniq.join("; ") if problems.any?

    @built = Piece.new(key: key, date: date, journal: journal, fiscal_year: year, description: cells.("description").compact.first, lines: lines)
    nil
  end

  def single(values, field, problems)
    values = values.compact
    problems << "the #{field} is missing" if values.empty?
    problems << "the lines of a piece give several values for the #{field}" if values.size > 1
    return unless values.size == 1

    block_given? ? yield(values.first) : values.first
  rescue ArgumentError => e
    problems << e.message
    nil
  end

  def line(row, file_line, analysis, problems)
    before = problems.size
    debit  = amount(cell(row, "debit"), file_line, problems)
    credit = amount(cell(row, "credit"), file_line, problems)
    problems << "line #{file_line}: one side only, a debit or a credit" if debit.positive? == credit.positive?
    account = account_for(cell(row, "account"), file_line, analysis, problems)
    partner = partner_for(cell(row, "partner"), file_line, analysis, problems)
    return if problems.size > before

    PieceLine.new(account: account, debit: debit, credit: credit, label: cell(row, "label"), partner: partner)
  end

  def amount(text, file_line, problems)
    parse_amount(text)
  rescue ArgumentError => e
    problems << "line #{file_line}: #{e.message}"
    BigDecimal("0")
  end

  def account_for(code, file_line, analysis, problems)
    return problems << "line #{file_line}: the account is missing" && nil unless code

    linked = @resolutions.dig("accounts", code) || code
    account = @accounts[linked]
    if account.nil?
      analysis.unknown("accounts", code)
      problems << "line #{file_line}: account #{code} is unknown"
    elsif !account.active? || !account.is_leaf?
      problems << "line #{file_line}: account #{linked} cannot take entries (archived or not a leaf)"
    end
    account
  end

  def partner_for(name, file_line, analysis, problems)
    return unless name

    resolution = @resolutions.dig("partners", name)
    found = (resolution.to_s.match?(/\A\d+\z/) && @partners.find { |p| p.id == resolution.to_i }) ||
            @partners.find { |p| p.external_ref == name || p.vat_number.to_s.delete(". ") == name.delete(". ") || p.name.casecmp?(name) }
    return found if found
    return name if resolution == "create"

    analysis.unknown("partners", name)
    problems << "line #{file_line}: partner #{name} is unknown"
    nil
  end
end
