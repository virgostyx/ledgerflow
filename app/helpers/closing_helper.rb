# What the closing assistant says about each step (F10): its result in a sentence, and the screen that explains it.
module ClosingHelper
  STATUS_CLASSES = {
    "ok" => "bg-emerald-100 text-emerald-800", "done" => "bg-emerald-100 text-emerald-800", "pending" => "bg-gray-100 text-gray-700",
    "warning" => "bg-amber-100 text-amber-800", "blocked" => "bg-red-100 text-red-800", "skipped" => "bg-gray-100 text-gray-500"
  }.freeze

  def closing_status_badge(step)
    label = step.warning? && step.acknowledged_at ? "Warning, acknowledged" : step.status.humanize
    tag.span(label, class: "inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{STATUS_CLASSES.fetch(step.status)}")
  end

  # The result of a step as short sentences, from what it found.
  def closing_step_lines(step)
    r = step.result || {}
    case step.code
    when "preparation" then [ r["next_year_missing"] ? "The next fiscal year does not exist yet." : (r["reason"] == "closed" ? "The year is closed." : "The next fiscal year exists.") ]
    when "entries_complete" then [ "#{pluralize(r['drafts'].to_i, 'entry')} in draft", "#{pluralize(r['tasks'].to_i, 'open closing task')}" ]
    when "bank" then Array(r["accounts"]).map { |a| "#{a['label']}: #{a['frozen'] ? 'reconciliation frozen' : 'no reconciliation frozen on the last day'}, gap #{a['gap_now']}" }
    when "partners" then [ "#{pluralize(r['balanced_groups'].to_i, 'balanced group')} of open lines not lettered" ] + Array(r["aged_balance_gaps"]).map { |g| "#{g['kind'].humanize}: aged balance #{g['aged_balance']} against account #{g['code']} #{g['account']}" }
    when "vat" then r["franchise"] ? [ "VAT franchise: nothing to file." ] : Array(r["periods"]).map { |p| "#{p['from']} to #{p['to']}: #{p['submitted'] ? 'declared' : 'not declared'}, #{p['locked'] ? 'locked' : 'not locked'}" }
    when "fixed_assets" then [ "#{pluralize(r['to_book'].to_i, 'asset')} with depreciation to book" ] + Array(r["i10_gaps"]).map { |g| "#{g['label']}: #{g['difference']}" }
    when "accruals" then [ "#{r['unbooked'].to_i} not booked, #{r['drafts'].to_i} to validate, #{r['missing_reversals'].to_i} without reversal" ] + Array(r["i11_gaps"]).map { |g| "#{g['label']}: #{g['difference']}" }
    when "suspense" then Array(r["accounts"]).map { |a| "#{a['code']} #{a['label']}: #{a['balance']}" }
    when "revaluation" then revaluation_lines(r)
    when "consistency" then [ "#{r['blocking'].to_i} blocking, #{r['warning'].to_i} warning, #{r['acknowledged'].to_i} acknowledged anomalies" ]
    when "analytical_review" then [ "#{Array(r['flagged']).size} heading(s) to comment, #{(r['comments'] || {}).size} commented", r["comparability"] ].compact
    when "closing_entries" then closing_entry_lines(r)
    when "carry_forward" then carry_lines(r)
    when "lock_and_bundle" then [ "Year and months locked: #{yes(r['locked'])}", "Snapshot: #{yes(r['snapshot'])}", "Closing file: #{yes(r['bundle'])}" ]
    else []
    end
  end

  # The report or screen that explains a step.
  def closing_step_link(step)
    year = step.run.fiscal_year
    case step.code
    when "entries_complete" then [ "Drafts", accounting_journal_entries_path(q: { status: "draft", fiscal_year_id: year.id }) ]
    when "bank" then [ "Bank reconciliation (R06)", accounting_reports_bank_reconciliation_report_path(as_of: year.end_date) ]
    when "partners" then [ "Open lines (R05)", accounting_reports_unlettered_lines_path ]
    when "vat" then [ "VAT declarations", accounting_vat_declarations_path ]
    when "fixed_assets" then [ "Fixed assets (R16)", accounting_reports_fixed_asset_movements_path(fiscal_year_id: year.id) ]
    when "accruals" then [ "Accruals", accounting_accruals_path ]
    when "suspense" then [ "Trial balance (R01)", accounting_reports_trial_balance_path(fiscal_year_id: year.id) ]
    when "revaluation" then [ "Foreign-currency balances", revaluation_accounting_fiscal_year_path(year) ]
    when "consistency" then [ "Consistency checks (R19)", accounting_consistency_runs_path ]
    when "analytical_review" then [ "Annual accounts (R07, R08)", accounting_reports_annual_accounts_path(fiscal_year_id: year.id) ]
    end
  end

  private

  def yes(value) = value ? "yes" : "no"

  def revaluation_lines(r)
    return [ "Closing rate missing for #{Array(r['missing_rates']).to_sentence}." ] if r["missing_rates"].present?
    return [ "Draft entry to validate." ] if r["draft_entry_id"]
    return Array(r["amounts"]).map { |a| "#{a['currency']}: unrealized #{a['kind']} of #{a['amount']} to draft" } if r["amounts"].present?

    [ "Nothing to book." ]
  end

  def closing_entry_lines(r)
    return [ "Nothing to close." ] if r["nothing_to_close"]
    return [ "Draft entry to validate." ] if r["draft_entry_id"]
    return [ "Income accounts still hold a balance: #{Array(r['not_at_zero']).map { |a| a['code'] }.join(', ')}." ] if r["not_at_zero"].present?
    return [ "#{r['accounts_to_close']} income account(s) to close." ] if r["accounts_to_close"]

    [ "The income accounts are closed." ]
  end

  def carry_lines(r)
    return [ "Waiting for the closing entry." ] if r["waiting_for"]
    return [ "To recalculate after the reopening: #{Array(r['differences']).size} account(s) differ." ] if r["stale"]
    return [ "Draft opening entry to validate." ] if r["draft_entry_id"]
    return [ "Opening entry to draft." ] if r["to_draft"]

    lines = Array(r["opening_mismatches"]).map { |m| "#{m['code']}: closing #{m['closing']}, opening #{m['opening']}" } + Array(r["aged_balance_gaps"]).map { |g| "#{g['kind'].humanize} aged balance differs for #{g['partners'].to_sentence}" }
    lines << "Archived partners with open lines: #{r['archived_partners'].to_sentence}." if r["archived_partners"].present?
    lines.presence || [ "Opening balances equal the closing balances; the aged balance is unchanged." ]
  end
end
