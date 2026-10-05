# F13c: entries through the API. A new entry is a draft; validating is an explicit action (`entries:post`, and the right of the owner to validate); a
# validated entry is never changed, it is reversed. The same models, policies and services as the screens: nothing here writes around them.
class Api::V1::Public::EntriesController < Api::V1::Public::BaseController
  SORTS = { "id" => "accounting_journal_entries.id", "entry_date" => "accounting_journal_entries.entry_date", "created_at" => "accounting_journal_entries.created_at" }.freeze
  FILTERS = {
    "status"      => ->(s, v) { s.where(status: v) },
    "journal"     => ->(s, v) { s.joins(:journal).where(accounting_journals: { code: v }) },
    "fiscal_year" => ->(s, v) { s.joins(:fiscal_year).where(accounting_fiscal_years: { year: v }) },
    "from"        => ->(s, v) { s.where("accounting_journal_entries.entry_date >= ?", v) },
    "to"          => ->(s, v) { s.where("accounting_journal_entries.entry_date <= ?", v) },
    "reference"   => ->(s, v) { s.where(reference: v) },
    "external_id" => ->(s, v) { s.where(external_id: v) }
  }.freeze

  self.action_scopes = { index: "entries:read", show: "entries:read", create: "entries:write", update: "entries:write", post: "entries:post", reverse: "entries:reverse" }

  def index
    page = paginate(scoped, sorts: SORTS, filters: FILTERS)
    return if performed?

    render json: { data: page[:rows].map { |entry| serialize(entry) }, meta: page[:meta] }
  end

  def show
    entry = find_entry
    response.set_header("ETag", etag(entry))
    render json: { data: serialize(entry) }
  end

  def create
    idempotently do
      entry, error = build_entry(payload)
      next unprocessable(error) if error
      next problem(:forbidden, "Forbidden", detail: "Your account may not enter in this journal.", slug: "forbidden") unless policy_for(entry).create?
      next problem(:conflict, "Already exists", detail: "An entry with this external_id exists.", slug: "already-exists") if entry.external_id && Accounting::JournalEntry.exists?(external_id: entry.external_id)

      save!(entry)
      render_entry(find_entry(entry.id), status: :created, location: true)
    end
  end

  def update
    entry = find_entry
    return problem(:forbidden, "Forbidden", detail: "Your account may not change entries of this journal.", slug: "forbidden") unless policy_for(entry).update?

    entry.with_lock do # the check of the ETag and the change are one step: a second writer finds the entry as the first left it
      next unless require_current!(etag(entry))
      next problem(:conflict, "Entry is validated", detail: "A validated entry is not changed: reverse it.", slug: "entry-validated") unless entry.draft?

      changed = apply_changes(entry, payload)
      next unprocessable(changed) if changed.is_a?(String)

      render_entry(find_entry(entry.id))
    end
  end

  def post
    entry = find_entry
    return problem(:forbidden, "Forbidden", detail: "Your account may not validate entries of this journal.", slug: "forbidden") unless policy_for(entry).post?
    return problem(:forbidden, "Four eyes", detail: "This entity requires a second person to validate your entry.", slug: "four-eyes") if entry.four_eyes_blocks?(@api_client.owner)

    result = Accounting::PostJournalEntry.call(entry: entry)
    return unprocessable(result.message) if result.failure?

    render_entry(find_entry(entry.id))
  end

  def reverse
    entry = find_entry
    return problem(:forbidden, "Forbidden", detail: "Your account may not reverse entries of this journal.", slug: "forbidden") unless policy_for(entry).reverse?

    result = Accounting::ReverseJournalEntry.call(entry: entry, reason: params[:reason].presence, date: params[:date].presence, user: @api_client.owner)
    return unprocessable(result.message) if result.failure?

    render_entry(find_entry(result[:reversal].id), status: :created, location: true)
  end

  private

  def scoped = Accounting::JournalEntry.includes(:journal, :fiscal_year, lines: :account)

  def find_entry(id = params[:id]) = scoped.find(id)

  def policy_for(entry) = Accounting::JournalEntryPolicy.new(@api_client.owner, entry)

  def payload = params.require(:entry).permit(:journal, :entry_date, :description, :external_id, lines: %i[account debit credit label partner_id currency]).to_h.deep_symbolize_keys

  def etag(entry) = etag_for("entry", entry.id, entry.status, entry.updated_at.iso8601(6), entry.lines.map { |l| [ l.id, l.updated_at.iso8601(6) ] })

  def render_entry(entry, status: :ok, location: false)
    response.set_header("ETag", etag(entry))
    response.set_header("Location", "/api/v1/entries/#{entry.id}") if location
    render json: { data: serialize(entry) }, status: status
  end

  def serialize(entry)
    { id: entry.id, reference: entry.reference, status: entry.status, entry_date: entry.entry_date.iso8601, journal: entry.journal.code, fiscal_year: entry.fiscal_year.year,
      description: entry.description, external_id: entry.external_id, created_at: entry.created_at.iso8601, updated_at: entry.updated_at.iso8601,
      lines: entry.lines.sort_by(&:id).map { |l| { id: l.id, account: l.account.code, partner_id: l.partner_id, label: l.label, debit: money(l.debit), credit: money(l.credit) } } }
  end

  def money(value) = format("%.2f", value)

  # => [entry, nil] or [nil, the reason it cannot be made]
  def build_entry(data)
    journal = Accounting::Journal.active.find_by(code: data[:journal])
    return [ nil, "journal #{data[:journal]} is unknown" ] unless journal

    date = parse_date(data[:entry_date]) or return [ nil, "entry_date must be a date, YYYY-MM-DD" ]
    year = Accounting::FiscalYear.open.find_by("start_date <= :d AND end_date >= :d", d: date)
    return [ nil, "there is no open fiscal year at #{date}" ] unless year

    lines = build_lines(data[:lines])
    return [ nil, lines ] if lines.is_a?(String)

    entry = Accounting::JournalEntry.new(journal: journal, fiscal_year: year, entry_date: date, description: data[:description], external_id: data[:external_id].presence,
                                         status: :draft, created_by: @api_client.owner)
    lines.each_with_index { |line, i| entry.lines.build(line.merge(sort_order: i)) }
    [ entry, nil ]
  end

  # => the lines as attributes, or a String
  def build_lines(raw)
    raw = Array(raw)
    return "an entry needs at least two lines" if raw.size < 2

    accounts = Accounting::Account.where(code: raw.map { |l| l[:account].to_s }).index_by(&:code)
    lines = raw.map do |line|
      account = accounts[line[:account].to_s] or return "account #{line[:account]} is unknown"
      return "account #{account.code} cannot take entries (archived or not a leaf)" unless account.active? && account.is_leaf?
      return "lines are in EUR only for now: a foreign currency goes through the screens (line on #{account.code})" if line[:currency].present? && line[:currency] != "EUR"

      debit, credit = amount(line[:debit]), amount(line[:credit])
      return "a line on #{account.code} has an amount that is not a positive number" unless debit && credit && debit >= 0 && credit >= 0
      return "a line on #{account.code} must be a debit or a credit, not both or neither" unless debit.positive? ^ credit.positive?

      { account: account, debit: debit, credit: credit, label: line[:label], partner_id: line[:partner_id] }
    end
    debit, credit = lines.sum { |l| l[:debit] }, lines.sum { |l| l[:credit] }
    debit == credit ? lines : "the entry does not balance: debit #{money(debit)}, credit #{money(credit)}"
  end

  def amount(value)
    value.blank? ? BigDecimal("0") : BigDecimal(value.to_s)
  rescue ArgumentError
    nil
  end

  def parse_date(value)
    value.present? ? Date.iso8601(value.to_s) : nil
  rescue Date::Error
    nil
  end

  def save!(entry)
    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry.save!
    end
  end

  # => nil when applied, else the reason
  def apply_changes(entry, data)
    attributes = {}
    if data.key?(:entry_date)
      date = parse_date(data[:entry_date]) or return "entry_date must be a date, YYYY-MM-DD"
      year = Accounting::FiscalYear.open.find_by("start_date <= :d AND end_date >= :d", d: date) or return "there is no open fiscal year at #{date}"
      attributes.merge!(entry_date: date, fiscal_year: year)
    end
    attributes[:description] = data[:description] if data.key?(:description)
    attributes[:external_id] = data[:external_id].presence if data.key?(:external_id)
    lines = data.key?(:lines) ? build_lines(data[:lines]) : nil
    return lines if lines.is_a?(String)

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      if lines
        Accounting::JournalEntryLine.where(journal_entry_id: entry.id).includes(:analytical_annotations).destroy_all
        entry.lines.reset
      end
      lines&.each_with_index { |line, i| entry.lines.create!(line.merge(sort_order: i)) }
      entry.update!(attributes.merge(updated_at: Time.current))
    end
    nil
  rescue ActiveRecord::RecordInvalid => e
    e.message
  end
end
