# The facts of a summary (A10a), one source after the other, all read through the services the reports and the screens already use, none through a model, each only if the person may see what it reads. A source gives
# items: a `text` made of counts and nothing else (it is what the e-mail carries), a `detail` with the names and figures (it stays in the application), a reference that opens the screen, a priority and
# whether it is `urgent` (it comes back until it is dealt with) or only worth saying when it changed (`changed`: its `state` differs from the one the last summary kept).
module Agent::Digest::Sources
  Item = Struct.new(:key, :section, :text, :detail, :ref, :ask, :priority, :urgent, :changed, :count, :state, keyword_init: true)

  SECTIONS = { "anomalies" => "Anomalies", "vat" => "VAT", "closing" => "Closing", "cash" => "Cash", "receivables" => "Receivables", "bank" => "Bank", "peppol" => "Received invoices", "documents" => "Documents", "tasks" => "Tasks" }.freeze
  # The question the button "Ask the assistant" puts for each section: fixed on the server, never taken from the page.
  ASK = { "anomalies" => "What should I fix first?", "vat" => "What VAT do we have for this quarter?", "closing" => "Are there anomalies to fix before the closing?", "cash" => "How is the cash forecast?",
          "receivables" => "Which customers are more than 60 days late?", "bank" => "Is the bank reconciled?", "peppol" => "What is waiting among the received invoices?", "documents" => "Which documents are waiting in the inbox?",
          "tasks" => "Which of my tasks are overdue?" }.freeze

  # => [Item], those of the sections the person may see. `previous`: the snapshot of the last summary (counts and fingerprints), to say what changed.
  def self.call(context:, previous:, today:)
    SECTIONS.keys.flat_map { |section| Array.wrap(send(section, context, previous, today)) }.compact
  end

  def self.anomalies(context, previous, today)
    return unless context.allows?("reports.view")

    run = Accounting::ConsistencyRun.latest_first.first or return
    acknowledged = Accounting::ConsistencyAcknowledgement.pluck(:fingerprint).to_set
    open = run.findings.where.not(fingerprint: acknowledged.to_a).where(severity: %w[blocking warning])
    seen = previous.fetch("anomalies", []).to_set
    fresh = open.reject { |finding| seen.include?(finding.fingerprint) }
    blocking = open.select { |finding| finding.severity == "blocking" }
    return if open.empty?

    Item.new(key: "anomalies", section: "anomalies", count: open.size, state: open.map(&:fingerprint),
             text: "#{blocking.size} blocking and #{open.size - blocking.size} other anomalies are open, #{fresh.size} new since the last summary.",
             detail: open.sort_by { |finding| finding.severity == "blocking" ? 0 : 1 }.first(3).map(&:message).join(" | "),
             ref: Agent::Screens.ref("consistency"), priority: blocking.any? ? 100 : 45, urgent: blocking.any?, changed: fresh.any?)
  end

  def self.vat(context, previous, today)
    return unless context.allows?("reports.view") && context.entity.vat_regime != "franchise"

    due = vat_due(today) or return
    days = (due[:due] - today).to_i
    return if days > 30

    Item.new(key: "vat", section: "vat", count: 1, text: days.negative? ? "A VAT return is overdue." : "A VAT return is due in #{days} day(s).", detail: "Period #{due[:from].iso8601} to #{due[:to].iso8601}, due #{due[:due].iso8601}.",
             ref: Agent::Screens.ref("vat"), priority: days <= 5 ? 90 : 50, urgent: days <= 5, state: days.clamp(-1, 5), changed: previous["vat"] != days.clamp(-1, 5))
  end

  # The period after the last declaration, when it has ended, and the day the return is due (the 20th of the following month).
  def self.vat_due(today)
    last = Accounting::VatDeclaration.order(:period_end).last or return
    from = last.period_end + 1
    to = last.quarterly? ? from.end_of_quarter : from.end_of_month
    return if to >= today

    { from: from, to: to, due: to.next_month.change(day: Accounting::CashForecastQuery::VAT_DUE_DAY) }
  end

  def self.closing(context, previous, today)
    return unless context.allows?("reports.view")

    year = Accounting::FiscalYear.current or return
    days = (year.end_date - today).to_i
    drafts = Accounting::JournalEntry.where(fiscal_year_id: year.id, status: Accounting::JournalEntry.statuses[:draft]).count
    return unless days.between?(0, 45) && drafts.positive?

    Item.new(key: "closing", section: "closing", count: drafts, text: "The fiscal year ends in #{days} day(s) and #{drafts} draft entries remain.", detail: "Fiscal year #{year.year}, ending #{year.end_date.iso8601}.",
             ref: Agent::Screens.ref("journal"), priority: 70, urgent: days <= 15, state: drafts, changed: previous["closing"] != drafts)
  end

  def self.cash(context, previous, today)
    return unless context.allows?("reports.view")

    week = Accounting::CashForecastQuery.new(start: today).call.weeks.find(&:alert) or return
    Item.new(key: "cash", section: "cash", count: 1, text: "The cash forecast goes below the threshold in the week of #{week.from.iso8601}.", detail: "Forecast closing balance #{Agent::ToolResult.money(week.closing)} EUR.",
             ref: Agent::Screens.ref("cash_forecast"), priority: 80, urgent: true, state: week.from.iso8601, changed: previous["cash"] != week.from.iso8601)
  end

  def self.receivables(context, previous, today)
    return unless context.allows?("reports.view")

    rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: today).call.select { |row| row.days_61_90 + row.over_90 > 0 }
    return if rows.empty?

    Item.new(key: "receivables", section: "receivables", count: rows.size, text: "#{rows.size} customer(s) have receivables more than 60 days late.",
             detail: rows.sort_by { |row| -(row.days_61_90 + row.over_90) }.first(3).map { |row| "#{row.partner_name} #{Agent::ToolResult.money(row.days_61_90 + row.over_90)} EUR" }.join(" | "),
             ref: Agent::Screens.ref("aged_balance"), priority: 60, urgent: false, state: rows.size, changed: previous["receivables"] != rows.size)
  end

  def self.bank(context, previous, today)
    return unless context.allows?("bank.match")

    count = Accounting::BankTransaction.pending.count
    counted(previous, "bank", count, "bank", "#{count} bank line(s) wait to be reconciled.", Agent::Screens.ref("bank"), 40) if count.positive?
  end

  def self.peppol(context, previous, today)
    return unless context.allows?("peppol.review")

    count = Accounting::PeppolMessage.inbound.where(status: %i[received needs_review]).count
    counted(previous, "peppol", count, "peppol", "#{count} received invoice(s) wait for a decision.", Agent::Screens.ref("peppol"), 50) if count.positive?
  end

  def self.documents(context, previous, today)
    return unless context.allows?("documents.view")

    count = Accounting::Document.inbox.count
    counted(previous, "documents", count, "documents", "#{count} document(s) wait in the inbox.", Agent::Screens.ref("documents"), 30) if count.positive?
  end

  def self.tasks(context, previous, today)
    count = Accounting::Task.visible_to(context.user).open_ones.where(assignee_id: context.user.id).overdue.count
    counted(previous, "tasks", count, "tasks", "#{count} of your task(s) are overdue.", Agent::Screens.ref("tasks"), 55) if count.positive?
  end

  def self.counted(previous, key, count, section, text, ref, priority)
    Item.new(key: key, section: section, count: count, text: text, detail: nil, ref: ref, priority: priority, urgent: false, state: count, changed: previous[key] != count)
  end
  private_class_method :counted
end
