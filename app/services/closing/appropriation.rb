# F10: the appropriation of the result after a closing (decided 2026-10-05, first version). The general meeting decides after the closing, so the entry is a DRAFT of
# the NEXT year, dated the day of the meeting, to be validated when it has decided. Only the legal reserve is covered: 5 % of the profit, until the reserve holds 10 % of the
# capital (a proposal worked out and shown, the amount stays the person's to set); the rest of the profit stays carried forward. Dividends, other reserves and the
# withholding tax on dividends are not covered yet. Debit the carried profit (the carry account of the entity), credit the legal reserve (130100, which must exist).
# The legal rule (the base of the 5 %, the effect of a loss brought forward) is a proposal to be checked by an accountant: see QUESTIONS.md.
module Closing::Appropriation
  RATE = BigDecimal("0.05")
  CEILING = BigDecimal("0.10")

  # => { profit:, capital:, reserve:, ceiling:, proposed:, carry_account:, reserve_account:, problem: }
  def self.proposal(run)
    base = { profit: BigDecimal("0"), capital: BigDecimal("0"), reserve: BigDecimal("0"), ceiling: BigDecimal("0"), proposed: BigDecimal("0"),
             carry_account: run.entity.closing_carry_account_code, reserve_account: Accounting::AccountCodes::LEGAL_RESERVE, problem: nil }
    return base.merge(problem: "The year is not closed yet.") unless run.closed?

    year = run.fiscal_year
    profit = Accounting::AnnualAccounts.new(fiscal_year: year).call.rows(:income).find { |row| row.code == "9904" }.amount
    balances = Accounting::TrialBalanceQuery.new(fiscal_year: year, exclude_closing: true).call
    credit_of = ->(prefix) { balances.select { |b| b.code.start_with?(prefix) }.sum(BigDecimal("0")) { |b| b.total_credit - b.total_debit } }
    capital, reserve = credit_of.("100"), credit_of.(Accounting::AccountCodes::LEGAL_RESERVE)
    ceiling = [ (CEILING * capital) - reserve, BigDecimal("0") ].max
    figures = base.merge(profit: profit, capital: capital, reserve: reserve, ceiling: ceiling)
    return figures.merge(problem: "There is no profit to appropriate.") unless profit.positive?
    return figures.merge(problem: "The legal reserve already holds 10 % of the capital.") unless ceiling.positive?

    figures.merge(proposed: [ (RATE * profit), ceiling ].min.round(2, half: :up))
  end

  # The appropriation of this run that is alive (a draft, or booked and not reversed), if there is one: neither a reversed one nor the reversal of one.
  def self.entry_of(run)
    Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::APPROPRIATION_SOURCE, source_id: run.id, reversal_of_id: nil).where.not(status: :reversed).order(:id).last
  end

  # The same, from the parameters of a form.
  def self.call_prepare(run:, user:, params:)
    date = begin
      Date.iso8601(params[:date].to_s)
    rescue Date::Error
      nil
    end
    return LightService::Context.make(run: run).tap { |c| c.fail!("Give the date of the general meeting, YYYY-MM-DD.") } unless date

    prepare!(run: run, user: user, amount: params[:amount], date: date, comment: params[:comment].to_s.strip)
  end

  # => ctx[:entry]
  def self.prepare!(run:, user:, amount:, date:, comment:)
    ctx = LightService::Context.make(run: run)
    return ctx.tap { |c| c.fail!("Only a person who may prepare a closing records the appropriation.") } unless UserEntity.current.find_by(user: user, entity: run.entity)&.allows?("closing.prepare")

    figures = proposal(run)
    return ctx.tap { |c| c.fail!(figures[:problem]) } if figures[:problem] && !figures[:problem].start_with?("The legal reserve already")

    value = parse(amount)
    return ctx.tap { |c| c.fail!("The amount must be a positive number of euros.") } unless value&.positive?
    return ctx.tap { |c| c.fail!("The amount exceeds the profit of the year (#{figures[:profit].to_s('F')}).") } if value > figures[:profit]

    year = run.fiscal_year
    next_year = Accounting::FiscalYear.find_by(start_date: year.end_date + 1)
    return ctx.tap { |c| c.fail!("The meeting date must be after the end of the year (#{year.end_date}).") } unless date.to_date > year.end_date
    return ctx.tap { |c| c.fail!("The meeting date must fall in the next fiscal year.") } unless next_year && date.to_date.between?(next_year.start_date, next_year.end_date)

    carry = Accounting::Account.find_by(code: figures[:carry_account])
    reserve = Accounting::Account.find_by(code: figures[:reserve_account])
    return ctx.tap { |c| c.fail!("Create the account #{figures[:reserve_account]} Legal reserve (and the carry account #{figures[:carry_account]}) in the chart of accounts first.") } unless carry && reserve

    existing = entry_of(run)
    return ctx.tap { |c| c.fail!("The appropriation is already booked (entry #{existing.reference}): reverse it first.") } if existing && !existing.draft?

    journal = Accounting::Journal.active.find_by(journal_type: :misc) or return ctx.tap { |c| c.fail!("No active miscellaneous journal.") }
    ApplicationRecord.transaction do
      existing&.destroy!
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: next_year, entry_date: date.to_date, status: :draft, created_by: user,
                                               source_type: Accounting::JournalEntry::APPROPRIATION_SOURCE, source_id: run.id,
                                               description: "Appropriation of the result of #{year.year} (legal reserve): #{comment}".strip)
      entry.lines.create!(account: carry, debit: value, credit: 0, label: "Appropriation of the result of #{year.year}", sort_order: 0)
      entry.lines.create!(account: reserve, debit: 0, credit: value, label: "Legal reserve", sort_order: 1)
      Accounting::AuditLog.record!(auditable: run, action: "result_appropriation_prepared", user: user,
                                   payload: { fiscal_year: year.year, amount: value.to_s("F"), date: date.to_date.iso8601, entry_id: entry.id, proposed: figures[:proposed].to_s("F") })
      ctx[:entry] = entry
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
  end

  def self.parse(amount)
    BigDecimal(amount.to_s).round(2, half: :up)
  rescue ArgumentError, TypeError
    nil
  end
  private_class_method :parse
end
