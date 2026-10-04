# Step 15 of the closing (F10): the closing entry. The income accounts (revenue and expense) are settled into the result account of the entity
# (`closing_result_account_code`, 699000 by default) by ONE balanced entry, dated at the last day, drafted by the step and validated by a person
# in a batch (Closing::ValidateEntries), never by the step. Idempotent: the entry the run already made is the one it returns.
class Closing::Steps::ClosingEntries < Closing::Step
  self.position = 15
  self.code     = "closing_entries"
  self.title    = "Closing entries"
  self.kind     = :action
  self.blocking = true

  def evaluate
    entry = existing
    return entry.posted? ? verified(entry) : pending("draft_entry_id" => entry.id, **(stale?(entry) ? { "stale" => true } : {})) if entry
    return pending("waiting_for" => "entries_of_earlier_steps", "drafts" => earlier_drafts.size) if earlier_drafts.any?
    return ok("nothing_to_close" => true) if nets.empty?

    pending("accounts_to_close" => nets.size)
  end

  # Drafts the closing entry. It comes after the entries of the earlier steps (the regularizations, the revaluation) are validated, which it must include: while
  # one waits, nothing is drafted; a draft made before they were validated is made again.
  def perform(user:)
    ctx = LightService::Context.make(entry: existing)
    return ctx.tap { |c| c.fail!("Validate the entries that the earlier steps drafted (regularizations, revaluation) before closing the income accounts.") } if earlier_drafts.any?

    if ctx[:entry]&.draft? && stale?(ctx[:entry])
      ctx[:entry].destroy!
      ctx[:entry] = nil
    end
    return ctx if ctx[:entry] || nets.empty?

    account = Accounting::Account.find_by(code: run.entity.closing_result_account_code)
    return ctx.tap { |c| c.fail!("The result account #{run.entity.closing_result_account_code} does not exist: create it or choose another in the closing settings.") } unless account

    journal = Accounting::Journal.where(journal_type: :misc, active: true).first
    return ctx.tap { |c| c.fail!("No active miscellaneous journal.") } unless journal

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      ctx[:entry] = draft(journal, account)
      Accounting::AuditLog.record!(auditable: run, action: "closing_entry_drafted", user: user, payload: { entry_id: ctx[:entry].id })
    end
    ctx
  end

  private

  def existing
    Accounting::JournalEntry.where(closing_run_id: run.id, source_type: Accounting::JournalEntry::CLOSING_SOURCE).where.not(status: :reversed).order(:id).last
  end

  # Entries of this run that are still drafts and are not the closing entry or the opening entry: those of the regularizations and of the revaluation.
  def earlier_drafts
    Accounting::JournalEntry.where(closing_run_id: run.id, status: :draft)
                            .where("source_type IS DISTINCT FROM ? AND source_type IS DISTINCT FROM ?", Accounting::JournalEntry::CLOSING_SOURCE, Accounting::JournalEntry::CARRY_FORWARD_SOURCE).to_a
  end

  # A draft that no longer says what the income accounts hold (an entry was validated after it was made).
  def stale?(entry)
    result_code = run.entity.closing_result_account_code
    drafted = entry.lines.includes(:account).reject { |l| l.account.code == result_code }.to_h { |l| [ l.account_id, l.credit - l.debit ] }
    drafted != nets.transform_values { |net| net }
  end

  # Account id => net (debit − credit) of every income account that holds a balance, the result account left out; the closing entry of an earlier
  # run of the year left out too, so that a year closed again reads like one never closed.
  def nets
    @nets ||= Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end, exclude_closing: true).call
                .select { |row| %w[expense revenue].include?(row.account_type) && row.code != run.entity.closing_result_account_code && !row.closing_net.zero? }
                .to_h { |row| [ row.id, row.closing_net ] }
  end

  def draft(journal, result_account)
    entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: fiscal_year, entry_date: year_end, status: :draft, closing_run_id: run.id,
                                             source_type: Accounting::JournalEntry::CLOSING_SOURCE, description: I18n.t("accounting.fiscal_years.closing_entry_description", year: fiscal_year.year))
    label = I18n.t("accounting.fiscal_years.closing_label")
    nets.each do |account_id, net|
      Accounting::JournalEntryLine.create!(journal_entry: entry, account_id: account_id, label: label, debit: net.negative? ? net.abs : 0, credit: net.positive? ? net : 0)
    end
    result = nets.values.sum
    Accounting::JournalEntryLine.create!(journal_entry: entry, account: result_account, label: label, debit: result.positive? ? result : 0, credit: result.negative? ? result.abs : 0)
    entry
  end

  # The entry is posted: the income accounts must be at zero.
  def verified(entry)
    left = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call
                                        .select { |row| %w[expense revenue].include?(row.account_type) && row.code != run.entity.closing_result_account_code && !row.balance.zero? }
    left.empty? ? ok("entry_id" => entry.id) : blocked("entry_id" => entry.id, "not_at_zero" => left.map { |r| { "code" => r.code, "balance" => money(r.balance) } })
  end
end
