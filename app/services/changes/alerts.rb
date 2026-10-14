# B03b R21: what a reviewer should look at first, computed from the changes of an interval (`Changes::Between` and `Changes::Events`). Thresholds are arguments with the
# defaults of the spec (late: 15 days).
class Changes::Alerts
  Alert = Struct.new(:kind, :subject_type, :subject_id, :detail, keyword_init: true)

  DEFAULTS = { late_days: 15, reversals_per_author: 5, mass_import: 50, unletterings: 3 }.freeze

  def self.call(**args) = new(**args).call

  # The thresholds the company set (the defaults are the specification's).
  def self.thresholds_of(entity)
    { late_days: entity.changes_late_days, reversals_per_author: entity.changes_reversals_per_author, mass_import: entity.changes_mass_import, unletterings: entity.changes_unletterings }
  end

  def initialize(changes:, events:, **thresholds)
    @changes = changes
    @events = events
    @limits = DEFAULTS.merge(thresholds)
  end

  def call = late + locked_period + frequent_reversals + mass_import + unlettering + iban_change

  private

  def entries = @entries ||= @changes.added.reject(&:reversal_of_id)

  # A reversal takes the date of what it undoes: it is not late for that.
  def late
    entries.filter_map do |e|
      days = (e.posted_at.in_time_zone.to_date - e.entry_date).to_i # the date of validation, in the time of the application like the dates of the books
      Alert.new(kind: :late, subject_type: "Accounting::JournalEntry", subject_id: e.id, detail: { days: days }) if days > @limits[:late_days]
    end
  end

  # An entry cannot be validated in a locked period: if its date is in the range of a lock that already existed, it got through an unlock or a controlled window.
  def locked_period
    locks = Accounting::PeriodLock.all.to_a
    (entries + @changes.reversals).filter_map do |e|
      lock = locks.find { |l| l.starts_on <= e.entry_date && e.entry_date <= l.ends_on && l.locked_at <= e.posted_at }
      Alert.new(kind: :locked_period, subject_type: "Accounting::JournalEntry", subject_id: e.id, detail: { lock_id: lock.id }) if lock
    end
  end

  def frequent_reversals
    @changes.reversals.group_by(&:author_id).filter_map do |author, list|
      Alert.new(kind: :frequent_reversals, subject_type: "User", subject_id: author, detail: { reversals: list.size }) if list.size >= @limits[:reversals_per_author]
    end
  end

  def mass_import
    ids = (@changes.added + @changes.reversals).map(&:id)
    batches = Accounting::JournalEntry.where(id: ids).where.not(import_batch_id: nil).group(:import_batch_id).count
    batches.filter_map do |batch, count|
      Alert.new(kind: :mass_import, subject_type: "Accounting::ImportBatch", subject_id: batch, detail: { entries: count, import_batch_id: batch }) if count >= @limits[:mass_import]
    end
  end

  def unlettering
    count = @events.count { |e| e.category == :lettering && e.action == "unletter" }
    count >= @limits[:unletterings] ? [ Alert.new(kind: :unlettering, detail: { count: count }) ] : []
  end

  def iban_change
    @events.select { |e| e.category == :iban && %w[bank_account_changed bank_account_superseded].include?(e.action) }
           .map { |e| Alert.new(kind: :iban_change, subject_type: e.subject_type, subject_id: e.subject_id, detail: { actor_id: e.actor_id }) }
  end
end
