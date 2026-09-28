# Generates the reversal of a booked accrual (R17) as a DRAFT entry on the first day of the next fiscal year:
# the same lines with debit and credit swapped, so the regularization disappears once the real invoice arrives.
class Accounting::ReverseAccrual
  def self.call(accrual:)
    ctx = LightService::Context.make(accrual: accrual)
    original = accrual.journal_entry
    return ctx.tap { |c| c.fail!("Book the regularization before reversing it.") } unless original
    return ctx.tap { |c| c.fail!("This regularization already has a reversal.") } if accrual.reversal_entry_id

    date = accrual.fiscal_year.end_date + 1
    next_year = Accounting::FiscalYear.where("start_date <= :d AND end_date >= :d", d: date).first
    return ctx.tap { |c| c.fail!("The next fiscal year does not exist yet.") } unless next_year
    return ctx.tap { |c| c.fail!(I18n.t("accounting.fixed_assets.errors.fiscal_year_closed")) } if next_year.closed?

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = Accounting::JournalEntry.create!(journal: original.journal, fiscal_year: next_year, entry_date: date, status: :draft,
                                               reference: "ACCR-REV-#{accrual.id}", description: "Reversal: #{original.description}")
      original.lines.each do |l|
        Accounting::JournalEntryLine.create!(journal_entry: entry, account: l.account, debit: l.credit, credit: l.debit, label: l.label)
      end
      accrual.update!(reversal_entry: entry)
    end
    ctx
  rescue StandardError => e
    ctx.tap { |c| c.fail!("Error: #{e.message}") }
  end
end
