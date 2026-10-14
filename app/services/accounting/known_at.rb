# B03a: an instant "as known" for the books of the current company. `seq` is the last place (`posted_seq`) validated at or before it: the entries beyond it did not exist
# yet. No instant, or one that is now or later, is today's view (`current?`, no filter). Before the start of the history the view is refused (`refused?`, `refusal`).
class Accounting::KnownAt
  class Refused < StandardError; end
  class Invalid < StandardError; end

  # An instant typed by a person: with its offset (ISO 8601) it is exact; without, it is the local time of the application, and a time that exists twice (the clock goes back) or
  # not at all (it goes forward) is refused, with the offset to give.
  def self.parse(value)
    text = value.to_s.strip
    raise Invalid, I18n.t("accounting.known_at.invalid") unless text.match?(/\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?\z/)
    text = text.sub(" ", "T").sub(/(T\d{2}:\d{2})(?!:)/, '\\1:00') # Time.iso8601 wants the seconds
    return Time.iso8601(text).in_time_zone if text.match?(/(Z|[+-]\d{2}:?\d{2})\z/)

    local = Time.utc(*text.scan(/\d+/).first(6).map(&:to_i))
    Time.zone.tzinfo.local_to_utc(local).in_time_zone
  rescue TZInfo::AmbiguousTime, TZInfo::PeriodNotFound
    raise Invalid, I18n.t("accounting.known_at.ambiguous")
  rescue ArgumentError
    raise Invalid, I18n.t("accounting.known_at.invalid")
  end

  attr_reader :time

  def self.wrap(value, fiscal_year: nil) = value.is_a?(self) ? value : new(value, fiscal_year: fiscal_year)

  def initialize(time, fiscal_year: nil)
    @time = time&.to_time
    @fiscal_year = fiscal_year
  end

  def history_start = @history_start ||= find_history_start

  def current? = time.nil? || time >= Time.current

  def refused? = !current? && time < history_start

  def refusal
    I18n.t("accounting.known_at.before_history", start: I18n.l(history_start, format: :long)) if refused?
  end

  # 0 when nothing was validated yet; nil for today's view.
  def seq
    return nil if current?

    @seq ||= Accounting::JournalEntry.where.not(posted_seq: nil).where(posted_at: ..time).maximum(:posted_seq) || 0
  end

  # Refuses a view before the start of the history; gives back self otherwise.
  def ensure_viewable!
    raise Refused, refusal if refused?

    self
  end

  # `scope` (joined to the entries, or on them) kept to what was known: the entries validated at or before the instant.
  def restrict(scope, table: "accounting_journal_entries")
    current? ? scope : scope.where("#{table}.posted_seq <= ?", seq)
  end

  # What a report said at a past instant does not change: it is kept without expiry, under the company, the report, the version of its figures and the instant. Today's view,
  # and an instant too recent to be sure that everything validated by then is committed, are computed each time.
  SETTLED_AFTER = 30.seconds
  SCHEMA_VERSION = 1 # raised when a report changes what it computes: the results kept under the old figures are then left behind

  def cache(report, parts)
    return yield if current? || time > SETTLED_AFTER.ago

    key = [ "known_at", ActsAsTenant.current_tenant.id, report, SCHEMA_VERSION, time.utc.iso8601(6), Digest::SHA256.hexdigest(parts.to_json) ]
    Rails.cache.fetch(key) { yield }
  end

  private

  def find_history_start
    scope = Accounting::HistoryStart.all
    (@fiscal_year && scope.find_by(fiscal_year_id: @fiscal_year.id)&.starts_at) || scope.find_by(fiscal_year_id: nil)&.starts_at || ActsAsTenant.current_tenant.created_at
  end
end
