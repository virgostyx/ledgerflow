# Drafts, for the accountant to check and post, the unrealized exchange LOSS of the fiscal year end (prudence: an
# unrealized gain is never booked): Dr 651200 / Cr 499100, one pair of lines per currency, dated at the closing date; and,
# once the next fiscal year exists, the mirror entry on its first day so the loss is not counted again when the items are
# settled (Accounting::Actions::PostFxAdjustment compares with the amount originally booked). Idempotent: a second call
# only adds the reversal if it was missing. Nothing is posted here; a missing closing rate or account refuses.
class Accounting::ProposeRevaluationEntry
  SOURCE = Accounting::JournalEntry::REVALUATION_SOURCE

  def self.call(fiscal_year:)
    ctx = LightService::Context.make(fiscal_year: fiscal_year)
    ApplicationRecord.transaction do
      error = new(fiscal_year, ctx).run
      ctx.fail!(error) if error
      raise ActiveRecord::Rollback if ctx.failure?
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}") unless ctx.failure?
    ctx
  end

  def initialize(fiscal_year, ctx)
    @fiscal_year = fiscal_year
    @ctx = ctx
  end

  def run
    existing = Accounting::JournalEntry.where(fiscal_year: @fiscal_year, source_type: SOURCE).find_by(entry_date: @fiscal_year.end_date)
    return add_reversal(existing) if existing

    rows = Accounting::ForeignRevaluationQuery.new(as_of: @fiscal_year.end_date).call
    return I18n.t("accounting.revaluation.errors.missing_rate", currencies: rows.select { |r| r.rate.nil? }.map(&:currency).uniq.join(", ")) if rows.any? { |r| r.rate.nil? }

    losses = rows.group_by(&:currency).transform_values { |r| -r.sum(BigDecimal("0")) { |x| [ x.difference, 0 ].min } }.select { |_, v| v.positive? }
    return I18n.t("accounting.revaluation.errors.no_loss") if losses.empty?

    accounts = lookup_accounts or return I18n.t("accounting.revaluation.errors.missing_account", codes: [ loss_code, Accounting::AccountCodes::FX_UNREALIZED ].join(" / "))
    journal = Accounting::Journal.where(journal_type: :misc, active: true).first or return I18n.t("accounting.revaluation.errors.no_journal")

    entry = draft(journal, @fiscal_year, @fiscal_year.end_date, losses, accounts, mirrored: false)
    @ctx[:entry] = entry
    add_reversal(entry)
    nil
  end

  private

  def loss_code = Accounting::AccountCodes::FX_LOSS

  def lookup_accounts
    loss = Accounting::Account.find_by(code: loss_code)
    unrealized = Accounting::Account.find_by(code: Accounting::AccountCodes::FX_UNREALIZED)
    { loss: loss, unrealized: unrealized } if loss && unrealized
  end

  def add_reversal(entry)
    @ctx[:entry] = entry
    next_year = Accounting::FiscalYear.find_by(start_date: @fiscal_year.end_date + 1)
    return unless next_year && !Accounting::JournalEntry.exists?(source_type: SOURCE, fiscal_year: next_year, entry_date: next_year.start_date)

    amounts = entry.lines.where("debit > 0").to_a.to_h { |l| [ l.label.split.last, l.debit ] }
    accounts = lookup_accounts or return I18n.t("accounting.revaluation.errors.missing_account", codes: loss_code)
    @ctx[:reversal] = draft(entry.journal, next_year, next_year.start_date, amounts, accounts, mirrored: true)
    nil
  end

  def draft(journal, fiscal_year, date, losses, accounts, mirrored:)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: journal, fiscal_year: fiscal_year, entry_date: date, status: :draft, source_type: SOURCE,
      description: mirrored ? "Reversal of unrealized FX losses at #{@fiscal_year.end_date}" : "Unrealized FX losses at #{@fiscal_year.end_date}"
    )
    zero = BigDecimal("0")
    losses.each do |currency, amount|
      label = "Unrealized FX loss #{currency}"
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: accounts[:loss], label: label,
                                           debit: mirrored ? zero : amount, credit: mirrored ? amount : zero)
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: accounts[:unrealized], label: label,
                                           debit: mirrored ? amount : zero, credit: mirrored ? zero : amount)
    end
    entry
  end
end
