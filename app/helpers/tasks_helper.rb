module TasksHelper
  STATUS_STYLES = { "open" => "bg-blue-100 text-blue-800", "in_progress" => "bg-indigo-100 text-indigo-800", "blocked" => "bg-red-100 text-red-800",
                    "done" => "bg-emerald-100 text-emerald-800", "cancelled" => "bg-gray-100 text-gray-600" }.freeze

  def task_status_badge(task) = tag.span(task.status.humanize, class: "text-xs px-2 py-1 rounded-full #{STATUS_STYLES.fetch(task.status)}")

  # A label for what a task is about, with a link to it when there is a page for it.
  def task_target_label(task)
    target = task.target
    return "—" unless target

    case target
    when Accounting::JournalEntry then link_to("Entry #{target.reference || "##{target.id}"}", accounting_journal_entry_path(target), class: "text-primary-700 hover:underline")
    when Accounting::JournalEntryLine then link_to("Line of entry #{target.journal_entry.reference || "##{target.journal_entry_id}"}", accounting_journal_entry_path(target.journal_entry), class: "text-primary-700 hover:underline")
    when Accounting::Partner then link_to(target.name, accounting_partner_path(target), class: "text-primary-700 hover:underline")
    when Accounting::Document then link_to(target.name, accounting_document_path(target), class: "text-primary-700 hover:underline")
    when Accounting::Invoice then link_to(target.invoice_number || "Invoice #{target.id}", accounting_invoice_path(target), class: "text-primary-700 hover:underline")
    when Accounting::Account then "Account #{target.code}"
    when Accounting::BankTransaction then "Bank line #{target.transaction_date}"
    when Accounting::PeriodLock then "Period #{target.starts_on} to #{target.ends_on}"
    else target.class.name.demodulize
    end
  end

  # May the current user make a task here? (the flag, the right, the thing seen)
  def task_allowed_for?(target)
    feature?(:f08) && Accounting::TaskPolicy.new(current_user, Accounting::Task.new(target: target)).create?
  end

  # The badge "n open tasks" of something, a link to them; `count` comes from Accounting::TaskBadges for a list, else it is counted.
  def task_badge(target, count: nil)
    return unless feature?(:f08)

    count ||= Accounting::TaskBadges.counts(target.class, [ target.id ]).fetch(target.id, 0)
    return if count.zero?

    link_to "#{count} task#{'s' if count > 1}", accounting_tasks_path(scope: "all", target_type: target.class.name, target_id: target.id),
            class: "ml-2 text-xs px-2 py-0.5 rounded-full bg-blue-100 text-blue-800", title: "Open tasks"
  end

  def task_link(target, label: "Add a task", **options)
    return unless task_allowed_for?(target)

    link_to label, new_accounting_task_path(target_type: target.class.name, target_id: target.id, **options), class: "text-primary-700 hover:underline text-sm"
  end
end
