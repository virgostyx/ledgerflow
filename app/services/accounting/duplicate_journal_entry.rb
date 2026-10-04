# F07: a draft copy of any entry (posted, reversed or draft): same journal, description and lines. Nothing of its life comes along: no
# reversal link, no source document, no reference (given when it is posted), no planned reversal. Dated today when an open fiscal year covers
# today, else like the original. => ctx[:entry]
class Accounting::DuplicateJournalEntry
  def self.call(entry:, user: nil)
    ctx = LightService::Context.make(entry: entry)
    date = Accounting::FiscalYear.open.exists?([ "start_date <= :d AND end_date >= :d", { d: Date.current } ]) ? Date.current : entry.entry_date
    year = Accounting::FiscalYear.open.find_by("start_date <= :d AND end_date >= :d", d: date)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.entry_templates.errors.no_fiscal_year", date: I18n.l(date))) } unless year

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      copy = Accounting::JournalEntry.create!(journal: entry.journal, fiscal_year: year, entry_date: date, status: :draft, description: entry.description, created_by: user)
      entry.lines.order(:sort_order, :id).each do |line|
        copy.lines.create!(account_id: line.account_id, partner_id: line.partner_id, label: line.label, debit: line.debit, credit: line.credit,
                           vat_code: line.vat_code, vat_amount: line.vat_amount, sort_order: line.sort_order)
      end
      ctx[:entry] = copy
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
  end
end
