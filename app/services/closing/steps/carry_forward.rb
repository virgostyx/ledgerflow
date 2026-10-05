# Step 16 of the closing (F10): the carry-forward. The opening entry of the next year, drafted by the step and validated by a person in a batch
# (Closing::ValidateEntries): the closing balances of classes 0 to 5, one line per account; the open lines of the customer and supplier accounts one by one,
# with their partner, their due date and the line they come from (`origin_line_id`: Accounting::OpenLineSql counts the carried line and no longer the
# original, so the aged balance of the first day of the new year is the one of the last day of the old); the result of the year, which the closing entry
# gathered in the result account, into the carry account (`closing_carry_account_code`, 140100 "Bénéfice reporté" by default) when it is a profit, into the loss account (`closing_loss_account_code`, 140200 "Perte
# reportée" by default) when it is a loss. The income accounts open at zero.
# Read once posted: opening balances against closing balances, and R04 against R04, or it blocks.
class Closing::Steps::CarryForward < Closing::Step
  self.position = 16
  self.code     = "carry_forward"
  self.title    = "Carry-forward"
  self.kind     = :action
  self.blocking = true

  def evaluate
    entry = existing
    return pending("waiting_for" => "closing_entries") unless entry || income_closed?
    return pending("next_year_missing" => true) unless next_year
    return pending("draft_entry_id" => entry.id) if entry&.draft?
    return pending("stale" => true, "stale_entry_ids" => stale_entries.map(&:id), "differences" => differences) if entry.nil? && stale_entries.any?
    return pending("to_draft" => true) unless entry

    verify(entry)
  end

  # Drafts the opening entry. After a reopening it is the recalculation: the opening entry of the first closing is reversed (refused if a line it carried was lettered
  # in the next year) and the new one drafted; `differences` says first what changes. Idempotent.
  def perform(user:)
    ctx = LightService::Context.make(entry: existing)
    return ctx if ctx[:entry]
    return ctx.tap { |c| c.fail!("The closing entry must be validated first: the income accounts are not closed.") } unless income_closed?
    return ctx.tap { |c| c.fail!("The next fiscal year does not exist: prepare it first (step 1).") } unless next_year

    carry = Accounting::Account.find_by(code: run.entity.closing_carry_account_code)
    return ctx.tap { |c| c.fail!("The carry account #{run.entity.closing_carry_account_code} does not exist: create it or choose another in the closing settings.") } unless carry
    loss = loss_account(carry)

    journal = Accounting::Journal.where(journal_type: :misc, active: true).first
    return ctx.tap { |c| c.fail!("No active miscellaneous journal.") } unless journal

    ApplicationRecord.transaction do
      problem = reverse_stale(user)
      next ctx.fail!(problem) && raise(ActiveRecord::Rollback) if problem

      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      ctx[:entry] = draft(journal, carry, loss)
      Accounting::ClosingRun.where(fiscal_year: fiscal_year, carry_forward_stale: true).update_all(carry_forward_stale: false)
      Accounting::AuditLog.record!(auditable: run, action: "closing_carry_forward_drafted", user: user, payload: { entry_id: ctx[:entry].id, recalculated: stale_entries.any? })
    end
    ctx
  end

  # What a recalculation changes, account by account, before it is done: [{code, label, old, new, difference, lines: {added, removed}}] for each account
  # whose balance or whose carried open lines differ. Amounts are debit − credit.
  def differences
    carry = Accounting::Account.find_by(code: run.entity.closing_carry_account_code)
    return [] unless carry

    loss = loss_account(carry)
    old_lines = Accounting::JournalEntryLine.where(journal_entry_id: stale_entries.map(&:id)).to_a
    old_nets = old_lines.group_by(&:account_id).transform_values { |lines| lines.sum { |l| l.debit - l.credit } }
    old_origins = old_lines.group_by(&:account_id).transform_values { |lines| lines.filter_map(&:origin_line_id) }
    new_nets = balances(carry, loss)
    new_origins = open_lines.group_by(&:account_id).transform_values { |lines| lines.map { |l| l.line.id } }
    accounts = Accounting::Account.where(id: old_nets.keys | new_nets.keys).index_by(&:id)

    (old_nets.keys | new_nets.keys).filter_map do |id|
      old = old_nets.fetch(id, BigDecimal("0"))
      new = new_nets.fetch(id, BigDecimal("0"))
      added = (new_origins.fetch(id, []) - old_origins.fetch(id, [])).size
      removed = (old_origins.fetch(id, []) - new_origins.fetch(id, [])).size
      next if old == new && added.zero? && removed.zero?

      { "code" => accounts.fetch(id).code, "label" => accounts.fetch(id).label_fr, "old" => money(old), "new" => money(new), "difference" => money(new - old),
        "lines" => { "added" => added, "removed" => removed } }
    end.sort_by { |d| d["code"] }
  end

  private

  def next_year = @next_year ||= Accounting::FiscalYear.find_by(start_date: year_end + 1)

  # The opening entries of an earlier closing of this year that was reopened since: still posted, to be recalculated.
  def stale_entries
    Accounting::JournalEntry.where(source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE, status: :posted, fiscal_year_id: next_year&.id,
                                   closing_run_id: Accounting::ClosingRun.where(fiscal_year: fiscal_year, carry_forward_stale: true).select(:id)).to_a
  end

  # Reverses them; a line they carried that was lettered in the next year stops it (the lettering would have to be undone first, by a person).
  def reverse_stale(user)
    stale_entries.each do |entry|
      lettered = Accounting::JournalEntryLine.where(journal_entry_id: entry.id).where.not(lettering_id: nil).count
      return "#{lettered} carried line(s) were lettered in the next year: unletter them before recalculating the carry-forward." if lettered.positive?

      reversed = Accounting::ReverseJournalEntry.call(entry: entry, from_source: true, user: user,
                                                      reason: "Carry-forward recalculated after the reopening of #{fiscal_year.year}")
      return reversed.message if reversed.failure?
    end
    nil
  end

  def existing = Accounting::JournalEntry.where(closing_run_id: run.id, source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE).where.not(status: :reversed).order(:id).last

  def income_closed? = Closing::Registry.fetch("closing_entries").new(run).evaluate.status == :ok

  # [account, closing net (debit − credit)] of the balance sheet accounts (classes 0 to 5) that hold a balance, the result account's net added to the carry account's.
  # The account that takes a loss: the loss account of the entity when the chart has it, else the carry account itself (a debit balance on it).
  def loss_account(carry) = Accounting::Account.find_by(code: run.entity.closing_loss_account_code) || carry

  def balances(carry, loss)
    rows = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call
    accounts = Accounting::Account.where(id: rows.map(&:id)).index_by(&:id)
    result_code = run.entity.closing_result_account_code
    nets = Hash.new(BigDecimal("0"))
    rows.each do |row|
      account = accounts.fetch(row.id)
      if row.code == result_code then nets[row.closing_net.positive? ? loss.id : carry.id] += row.closing_net
      elsif (0..5).cover?(account.account_class) then nets[account.id] += row.closing_net
      end
    end
    nets.reject { |_, net| net.zero? }
  end

  def draft(journal, carry, loss)
    entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: next_year, entry_date: next_year.start_date, status: :draft, closing_run_id: run.id,
                                             source_type: Accounting::JournalEntry::CARRY_FORWARD_SOURCE,
                                             description: I18n.t("accounting.fiscal_years.opening_entry_description", year: fiscal_year.year))
    label = I18n.t("accounting.fiscal_years.opening_entry_label")
    nets = balances(carry, loss)
    detailed = open_lines
    nets.each do |account_id, net|
      lines = detailed.select { |line| line.account_id == account_id }
      lines.each { |line| carried_line(entry, line) }
      rest = net - lines.sum { |l| l.debit - l.credit }
      add(entry, account_id, rest, label) unless rest.zero? # what the account holds that no open line explains (nothing, once step 4 is ok)
    end
    entry
  end

  # The open lines of the partner accounts at the last day, as the lines they carry: same side, what is left of them, the due date they have now.
  def open_lines
    rows = Accounting::UnletteredLinesQuery.new(kind: :both, as_of: year_end).call.reject { |r| r.residual.zero? }
    originals = Accounting::JournalEntryLine.includes(:journal_entry).where(id: rows.map(&:line_id)).index_by(&:id)
    rows.map do |row|
      line = originals.fetch(row.line_id)
      CarriedLine.new(account_id: line.account_id, line: line, due_date: row.due_date, amount: row.residual.abs, debit_side: line.debit.positive?)
    end
  end

  CarriedLine = Struct.new(:account_id, :line, :due_date, :amount, :debit_side, keyword_init: true) do
    def debit = debit_side ? amount : BigDecimal("0")
    def credit = debit_side ? BigDecimal("0") : amount
  end
  private_constant :CarriedLine

  def carried_line(entry, carried)
    original = carried.line
    share = carried.amount / (original.debit + original.credit)
    foreign = original.currency == "EUR" || original.amount_currency.nil? ? {} :
      { currency: original.currency, exchange_rate: original.exchange_rate, amount_currency: (original.amount_currency * share).round(Accounting::Currency.decimals_of(original.currency)) }
    Accounting::JournalEntryLine.create!(journal_entry: entry, account_id: carried.account_id, partner_id: original.partner_id, invoice_id: original.invoice_id, origin_line_id: original.id,
                                         due_date: carried.due_date, label: "#{I18n.t('accounting.fiscal_years.opening_entry_label')} #{original.journal_entry.reference}".strip,
                                         debit: carried.debit, credit: carried.credit, **foreign)
  end

  def add(entry, account_id, net, label)
    Accounting::JournalEntryLine.create!(journal_entry: entry, account_id: account_id, label: label, debit: net.positive? ? net : 0, credit: net.negative? ? net.abs : 0)
  end

  # The opening entry is posted: criterion 2 (opening = closing for classes 0 to 5, the income accounts open at zero) and criterion 3 (R04 unchanged).
  def verify(entry)
    carry_code = run.entity.closing_carry_account_code
    loss_code = loss_account(Accounting::Account.find_by(code: carry_code))&.code # (the carry account itself when the chart has no loss account)
    result_code = run.entity.closing_result_account_code
    result_net = nil
    closing = Accounting::TrialBalanceQuery.new(fiscal_year: fiscal_year, as_of: year_end).call.index_by(&:code)
    opening = Accounting::TrialBalanceQuery.new(fiscal_year: next_year, as_of: next_year.start_date).call.index_by(&:code)
    classes = Accounting::Account.where(id: (closing.values + opening.values).map(&:id)).index_by(&:id)

    mismatches = (closing.keys | opening.keys).filter_map do |code|
      account = classes[(closing[code] || opening[code]).id]
      next unless (0..5).cover?(account.account_class) || code == result_code

      result_net ||= closing[result_code]&.closing_net.to_d || BigDecimal("0")
      takes_result = code == (result_net.positive? ? loss_code : carry_code) # a profit goes to the carry account, a loss to the loss account
      expected = code == result_code ? BigDecimal("0") : closing[code]&.closing_net.to_d + (takes_result ? result_net : 0)
      actual = opening[code]&.closing_net.to_d
      { "code" => code, "closing" => money(expected), "opening" => money(actual) } unless expected == actual
    end
    aged = %i[customer supplier].filter_map { |kind| aged_gap(kind, next_year) }
    details = { "entry_id" => entry.id, "opening_mismatches" => mismatches, "aged_balance_gaps" => aged }
    return blocked(details) if mismatches.any? || aged.any?

    archived = Accounting::Partner.where(active: false, id: entry.lines.select(:partner_id)).pluck(:name)
    archived.any? ? warning(details.merge("archived_partners" => archived)) : ok(details)
  end

  def aged_gap(kind, following)
    totals = ->(date) { Accounting::AgedBalanceQuery.new(kind: kind, as_of: date).call.to_h { |r| [ r.partner_name, r.total ] } }
    before = totals.(year_end)
    after = totals.(following.start_date)
    return if before == after

    { "kind" => kind.to_s, "partners" => (before.keys | after.keys).select { |name| before[name] != after[name] } }
  end
end
