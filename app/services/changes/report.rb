# B03b R21, the report as a whole: the summary, the impact on the accounts, the closing (I14), the detail in chronological order, the review alerts. It is built from
# `Changes::Between` (entries and impact), `Changes::Events` (the other categories) and `Changes::Alerts`.
#
# Who may see the names of the authors is the caller's to say (`show_authors:`, the right `audit.view`): without it no name, no identifier of a person leaves this class.
# The filters of journals and accounts narrow the entries and the impact; the closing is always that of the whole perimeter of the fiscal year.
class Changes::Report
  ENTRY_CATEGORIES = %i[entries reversals].freeze
  CATEGORIES = (ENTRY_CATEGORIES + Changes::Events::CATEGORIES).freeze
  HIDDEN = "A user of the company".freeze
  FORMER = "Former user".freeze

  Detail = Struct.new(:key, :category, :at, :action, :author_id, :author, :reason, :subject_type, :subject_id, :label, :amount, :neutral, :reviewed_by, :reviewed_at, :comment, :detail,
                      keyword_init: true)
  Summary = Struct.new(:entries, :reversals, :neutral_pairs, :movements, :accounts, :letterings, :unletterings, :setup_changes, :locks, :unlocks, :actors, keyword_init: true)
  Result = Struct.new(:from, :to, :as_of, :summary, :impact, :closing, :details, :total, :alerts, :by_month, :statements, :page, :per, keyword_init: true)

  def self.call(**args) = new(**args).call

  def initialize(fiscal_year:, from:, to: nil, as_of: nil, show_authors: false, categories: nil, journal_ids: nil, actor_ids: nil, account_codes: nil, hide_neutral: false,
                 page: 1, per: 100, month_threshold: 300, statements: true, **thresholds)
    @fiscal_year = fiscal_year
    @from = from
    @to = to
    @as_of = as_of
    @show_authors = show_authors
    @categories = categories ? Array(categories).map(&:to_sym) & CATEGORIES : CATEGORIES
    @journal_ids = Array(journal_ids).presence
    @actor_ids = Array(actor_ids).presence
    @account_codes = Array(account_codes).presence
    @hide_neutral = hide_neutral
    @page = [ page.to_i, 1 ].max
    @per = per
    @month_threshold = month_threshold
    @statements = statements
    @thresholds = thresholds
  end

  def call
    between = Changes::Between.call(fiscal_year: @fiscal_year, from: @from, to: @to, as_of: @as_of)
    events = Changes::Events.call(from: between.from, to: between.to, categories: @categories & Changes::Events::CATEGORIES)
    details = entry_details(between) + event_details(events)
    details = details.sort_by { |d| [ d.at, d.key ] }
    details = details.reject(&:neutral) if @hide_neutral
    reviews = Changes::Review.reviewed(details.map(&:key))
    details.each { |d| review_of(d, reviews[d.key]) }
    names = names_of(details.map(&:author_id).compact)
    details.each { |d| name(d, names) }

    Result.new(from: between.from, to: between.to, as_of: between.as_of, summary: summary(between, events), impact: impact(between), closing: between.closing, total: details.size,
               details: page_of(details), alerts: alerts(between, events, names), by_month: (by_month(between) if wide?(between)), statements: (Changes::Statements.call(fiscal_year: @fiscal_year, from: between.from, to: between.to, as_of: between.as_of) if @statements),
               page: @page, per: @per)
  end

  private

  def entry_details(between)
    pairs = between.neutral_pairs.flatten.to_set
    rows = []
    rows += between.added.map { |e| [ :entries, e ] } if @categories.include?(:entries)
    rows += between.reversals.map { |e| [ :reversals, e ] } if @categories.include?(:reversals)
    allowed = allowed_entry_ids(rows.map { |_, e| e.id })
    rows.select { |_, e| allowed.include?(e.id) && (@actor_ids.nil? || @actor_ids.include?(e.author_id)) }.map do |category, e|
      Detail.new(key: "entry:#{e.id}", category: category, at: e.posted_at, action: category == :entries ? "posted" : "reversed", author_id: e.author_id, reason: e.reason,
                 subject_type: "Accounting::JournalEntry", subject_id: e.id, label: [ e.reference, e.description ].compact.join(" - "), amount: e.amount, neutral: pairs.include?(e.id),
                 detail: { entry_date: e.entry_date, journal_id: e.journal_id, posted_seq: e.posted_seq, reversal_of_id: e.reversal_of_id })
    end
  end

  # The journals and accounts asked for narrow the entries: those in the journals, with a line in the accounts.
  def allowed_entry_ids(ids)
    return ids.to_set if ids.empty? || (@journal_ids.nil? && @account_codes.nil?)

    scope = Accounting::JournalEntry.where(id: ids)
    scope = scope.where(journal_id: @journal_ids) if @journal_ids
    scope = scope.where(id: Accounting::JournalEntryLine.joins(:account).where(account_code_sql, *code_patterns).select(:journal_entry_id)) if @account_codes
    scope.pluck(:id).to_set
  end

  def account_code_sql = (@account_codes.map { "accounting_accounts.code LIKE ?" }).join(" OR ")
  def code_patterns = @account_codes.map { |c| "#{c}%" }

  def event_details(events)
    events.select { |e| @actor_ids.nil? || @actor_ids.include?(e.actor_id) }.map do |e|
      Detail.new(key: Changes::Key.for(e), category: e.category, at: e.at, action: e.action, author_id: e.actor_id, reason: e.reason, subject_type: e.subject_type, subject_id: e.subject_id,
                 neutral: false, detail: e.detail)
    end
  end

  def review_of(detail, review)
    return unless review

    detail.reviewed_by = review.reviewer&.email
    detail.reviewed_at = review.reviewed_at
    detail.comment = review.comment
  end

  # The name stays in the history: a person who left the company is marked, not erased.
  def names_of(ids)
    present = UserEntity.current.where(entity_id: ActsAsTenant.current_tenant.id, user_id: ids).pluck(:user_id).to_set
    User.where(id: ids).pluck(:id, :email).to_h { |id, email| [ id, present.include?(id) ? email : "#{email} (#{FORMER.downcase})" ] }
  end

  def name(detail, names)
    id = detail.author_id
    detail.author = id.nil? ? nil : (@show_authors ? names.fetch(id, FORMER) : HIDDEN)
    detail.author_id = nil unless @show_authors
  end

  def impact(between)
    return between.impact unless @account_codes

    between.impact.select { |r| @account_codes.any? { |c| r.code.to_s.start_with?(c) } }
  end

  def summary(between, events)
    count = ->(category, action = nil) { events.count { |e| e.category == category && (action.nil? || e.action == action) } }
    actors = (between.added + between.reversals).map(&:author_id) + events.map(&:actor_id)
    Summary.new(**between.summary.to_h, letterings: count.(:lettering, "letter"), unletterings: count.(:lettering, "unletter"), setup_changes: count.(:setup), locks: count.(:locks, "lock_period"),
                               unlocks: count.(:locks, "unlock_period"), actors: actors.compact.uniq.size)
  end

  # The people named in an alert are shown to who may see them only.
  def alerts(between, events, names)
    Changes::Alerts.call(changes: between, events: events, **@thresholds).map do |a|
      next a if @show_authors

      a.detail = a.detail.except(:actor_id)
      a.subject_id = nil if a.subject_type == "User"
      a
    end
  end

  def wide?(between) = ((between.to || Time.current) - between.from) / 1.day > @month_threshold

  def by_month(between)
    (between.added + between.reversals).group_by { |e| e.posted_at.to_date.beginning_of_month }.sort.map do |month, list|
      { month: month, entries: list.size, amount: list.sum(BigDecimal("0"), &:amount) }
    end
  end

  def page_of(details) = @per ? details.slice((@page - 1) * @per, @per) || [] : details
end
