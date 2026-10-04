# The revaluation of the foreign-currency balances at a closing date (F11): the open receivables, payables and bank balances in a foreign currency,
# valued at the closing rate (Fx::RateFor.closing), against what the books carry in EUR. Called by the closing (F10) or from the revaluation screen.
#
# What is drafted follows the entity's treatment: an unrealized loss is expensed (Dr loss account / Cr 499100) or left; an unrealized gain is left
# (the default: it is not booked before it is realized), deferred (Dr 499200 / Cr 492200, the profit and loss untouched) or recognized (Dr 499200 / Cr
# gain account). Each position counts on its own: a gain on one never offsets a loss on another. One DRAFT entry, dated at the closing date, whose
# reversal is scheduled for the next day (`auto_reverse_on`, Accounting::AutoReverseEntriesJob); a person checks and posts it. Idempotent: asked
# again, it returns the entry it already made. Refuses, saying why, without a closing rate or an account it needs. => ctx[:entry]
class Fx::Revalue
  SOURCE = Accounting::JournalEntry::REVALUATION_SOURCE

  def self.call(fiscal_year:, as_of: fiscal_year.end_date)
    ctx = LightService::Context.make(fiscal_year: fiscal_year, entry: nil)
    ApplicationRecord.transaction do
      error = new(fiscal_year, as_of, ctx).run
      ctx.fail!(error) if error
      raise ActiveRecord::Rollback if ctx.failure?
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}") unless ctx.failure?
    ctx
  end

  # What a revaluation would book, without booking it (F10 reads it to know whether the step has anything to do): the currencies that have a position but
  # no closing rate, and the amounts [[currency, :loss | :gain, amount], ...] the entity's treatment books.
  Plan = Struct.new(:missing, :amounts)

  def self.plan(fiscal_year:, as_of: fiscal_year.end_date)
    revalue = new(fiscal_year, as_of, nil)
    rows = Accounting::ForeignRevaluationQuery.new(as_of: as_of).call
    Plan.new(rows.select { |r| r.rate.nil? }.map(&:currency).uniq, revalue.send(:amounts_to_book, rows))
  end

  # The draft entry of the closing date, when there is one that is not reversed.
  def self.existing(fiscal_year:, as_of: fiscal_year.end_date)
    Accounting::JournalEntry.where(fiscal_year: fiscal_year, source_type: SOURCE, entry_date: as_of).where.not(status: :reversed).first
  end

  def initialize(fiscal_year, as_of, ctx)
    @fiscal_year = fiscal_year
    @as_of = as_of
    @ctx = ctx
    @entity = ActsAsTenant.current_tenant
  end

  def run
    existing = self.class.existing(fiscal_year: @fiscal_year, as_of: @as_of)
    return @ctx[:entry] = existing if existing

    rows = Accounting::ForeignRevaluationQuery.new(as_of: @as_of).call
    missing = rows.select { |r| r.rate.nil? }.map(&:currency).uniq
    return missing_rate_message(missing) if missing.any?

    amounts = amounts_to_book(rows)
    return I18n.t("accounting.revaluation.errors.nothing_to_book") if amounts.empty?

    journal = Accounting::Journal.where(journal_type: :misc, active: true).first or return I18n.t("accounting.revaluation.errors.no_journal")
    accounts = lookup(amounts) or return @missing_accounts_message
    @ctx[:entry] = draft(journal, amounts, accounts)
    nil
  end

  private

  def missing_rate_message(currencies)
    message = Fx::MissingRate.new(currencies.first, @as_of, kind: "closing").message
    currencies.size > 1 ? "#{message} Also missing: #{currencies.drop(1).join(', ')}." : message
  end

  # [[currency, :loss | :gain, amount], ...]: per position, a loss is booked as an expense when the entity says so, a gain as it says.
  def amounts_to_book(rows)
    rows.group_by(&:currency).flat_map do |currency, group|
      differences = group.filter_map(&:difference) # a position without a closing rate has none: it is reported as missing, not booked
      loss = differences.sum(BigDecimal("0")) { |d| [ -d, 0 ].max }
      gain = differences.sum(BigDecimal("0")) { |d| [ d, 0 ].max }
      [ (loss.positive? && @entity.unrealized_loss_expense? ? [ currency, :loss, loss ] : nil),
        (gain.positive? && !@entity.unrealized_gain_ignore? ? [ currency, :gain, gain ] : nil) ].compact
    end
  end

  def lookup(amounts)
    kinds = amounts.map { |_, kind, _| kind }.uniq
    needed = {}
    needed[:loss] = @entity.fx_loss_account_code if kinds.include?(:loss)
    needed[:unrealized_loss] = Accounting::AccountCodes::FX_UNREALIZED if kinds.include?(:loss)
    if kinds.include?(:gain)
      needed[:unrealized_gain] = Accounting::AccountCodes::FX_UNREALIZED_GAIN
      needed[:gain_to] = @entity.unrealized_gain_defer? ? Accounting::AccountCodes::FX_DEFERRED_GAIN : @entity.fx_gain_account_code
    end
    found = needed.transform_values { |code| Accounting::Account.find_by(code: code) }
    absent = needed.select { |key, _| found[key].nil? }.values
    return found if absent.empty?

    @missing_accounts_message = I18n.t("accounting.revaluation.errors.missing_account", codes: absent.uniq.join(" / "))
    nil
  end

  def draft(journal, amounts, accounts)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    entry = Accounting::JournalEntry.create!(
      journal: journal, fiscal_year: @fiscal_year, entry_date: @as_of, status: :draft, source_type: SOURCE, auto_reverse_on: @as_of + 1,
      description: "Unrealized exchange differences at #{@as_of}"
    )
    amounts.each do |currency, kind, amount|
      label = kind == :loss ? "Unrealized FX loss #{currency}" : "Unrealized FX gain #{currency}"
      debit_account, credit_account = kind == :loss ? [ accounts[:loss], accounts[:unrealized_loss] ] : [ accounts[:unrealized_gain], accounts[:gain_to] ]
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: debit_account, label: label, debit: amount, credit: 0)
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: credit_account, label: label, debit: 0, credit: amount)
    end
    entry
  end
end
