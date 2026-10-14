# B03b R21: what changed in the books between two instants T1 and T2 (the instants of B03a), for one fiscal year and one cut-off `as_of` common to both: the same accounting
# perimeter, known at two moments. The impact of an account is read from R01 at T1 and at T2 (the very report, `known_at:`); the movements are summed from the lines validated
# between the two places (`posted_seq`); the closing (I14) is that the two agree, account by account.
class Changes::Between
  class Invalid < StandardError; end

  Summary = Struct.new(:entries, :reversals, :movements, :accounts, :neutral_pairs, keyword_init: true)
  Added = Struct.new(:id, :reference, :entry_date, :posted_at, :posted_seq, :author_id, :journal_id, :amount, :description, :reversal_of_id, :reason, keyword_init: true)
  Impact = Struct.new(:account_id, :code, :label, :at_t1, :at_t2, :variation, :movements, keyword_init: true)
  Closing = Struct.new(:gaps, keyword_init: true) do
    def balanced? = gaps.empty?
    def gap = gaps.values.sum(BigDecimal("0")).abs
  end
  Result = Struct.new(:from, :to, :as_of, :added, :reversals, :neutral_pairs, :impact, :closing, :summary, keyword_init: true)

  def self.call(**args) = new(**args).call

  def initialize(fiscal_year:, from:, to: nil, as_of: nil)
    @fiscal_year = fiscal_year
    @as_of = as_of || fiscal_year.end_date
    @t1 = Accounting::KnownAt.new(from, fiscal_year: fiscal_year).ensure_viewable!
    @t2 = Accounting::KnownAt.new(to, fiscal_year: fiscal_year).ensure_viewable!
    raise Invalid, I18n.t("changes.errors.inverted") if !@t2.current? && @t1.time && @t1.time > @t2.time
  end

  def call
    entries = changed_entries
    reversals = entries.select(&:reversal_of_id)
    pairs = neutral_pairs(entries)
    impact = impact_rows
    Result.new(from: @t1.time, to: @t2.time, as_of: @as_of, added: entries.reject(&:reversal_of_id), reversals: reversals, neutral_pairs: pairs, impact: impact,
               closing: Closing.new(gaps: impact.to_h { |r| [ r.account_id, r.variation - r.movements ] }.reject { |_, gap| gap.zero? }),
               summary: Summary.new(entries: entries.size - reversals.size, reversals: reversals.size, accounts: impact.size, neutral_pairs: pairs.size,
                                    movements: entries.sum(BigDecimal("0"), &:amount)))
  end

  private

  def last_seq = @last_seq ||= Accounting::JournalEntry.maximum(:posted_seq) || 0

  def low = @t1.seq || last_seq
  def high = @t2.seq || last_seq

  def window(scope) = scope.where("accounting_journal_entries.posted_seq > ? AND accounting_journal_entries.posted_seq <= ?", low, high)

  def ledger_entries
    Accounting::JournalEntry.where(fiscal_year_id: @fiscal_year.id, status: Accounting::JournalEntry.ledger_status_values).where("accounting_journal_entries.entry_date <= ?", @as_of)
  end

  # One row per entry with its total, read in one query (plucked: ten thousand entries are not ten thousand objects).
  def changed_entries
    columns = %w[id reference entry_date posted_at posted_seq created_by_id journal_id description reversal_of_id reversal_reason].map { |c| "accounting_journal_entries.#{c}" }
    window(ledger_entries).joins(:lines).group("accounting_journal_entries.id").order("accounting_journal_entries.posted_seq")
      .pluck(*columns, Arel.sql("SUM(accounting_journal_entry_lines.debit)")).map do |id, reference, entry_date, posted_at, seq, author, journal, description, reversal_of, reason, total|
        Added.new(id: id, reference: reference, entry_date: entry_date, posted_at: posted_at, posted_seq: seq, author_id: author, journal_id: journal, amount: BigDecimal(total.to_s),
                  description: description, reversal_of_id: reversal_of, reason: reason)
      end
  end

  # [original, reversal] when both were validated inside the interval.
  def neutral_pairs(entries)
    ids = entries.map(&:id).to_set
    entries.select { |e| e.reversal_of_id && ids.include?(e.reversal_of_id) }.map { |e| [ e.reversal_of_id, e.id ] }
  end

  def impact_rows
    before = trial_balance(@t1.current? ? Time.current : @t1.time)
    after = trial_balance(@t2.time)
    moved = movements
    (before.keys | after.keys | moved.keys).filter_map do |id|
      b = before[id]
      a = after[id]
      account = a || b
      at1 = b&.closing_net || BigDecimal("0")
      at2 = a&.closing_net || BigDecimal("0")
      next if at1.zero? && at2.zero? && moved.fetch(id, 0).zero? && !moved.key?(id)

      Impact.new(account_id: id, code: account&.code || Accounting::Account.find(id).code, label: account&.label_fr, at_t1: at1, at_t2: at2, variation: at2 - at1, movements: moved.fetch(id, BigDecimal("0")))
    end.sort_by(&:code)
  end

  def trial_balance(time)
    Accounting::TrialBalanceQuery.new(fiscal_year: @fiscal_year, as_of: @as_of, known_at: time).call.index_by(&:id)
  end

  def movements
    lines = window(Accounting::JournalEntryLine.joins(:journal_entry).merge(ledger_entries))
    lines.group(:account_id).sum("accounting_journal_entry_lines.debit - accounting_journal_entry_lines.credit").transform_values { |v| BigDecimal(v.to_s) }
  end
end
