# Books an accrual/deferral (R17) as one balanced DRAFT entry in the miscellaneous journal, dated at the
# fiscal year end (the cut-off), for the user to validate. Debit/credit follow the type:
# deferred charge  D accrual account (490) / C charge     | accrued income D accrual account (490) / C income
# accrued charge   D charge / C accrual account (492)     | deferred income D income / C accrual account (492)
class Accounting::BookAccrual
  def self.call(accrual:)
    ctx = LightService::Context.make(accrual: accrual)
    fiscal_year = accrual.fiscal_year
    cut_off = fiscal_year.end_date
    amount = accrual.amount_at(cut_off)
    error = refusal(accrual, fiscal_year, amount)
    return ctx.tap { |c| c.fail!(error) } if error

    journal = Accounting::Journal.active.find_by(journal_type: :misc)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.fixed_assets.errors.no_misc_journal")) } unless journal

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = Accounting::JournalEntry.create!(journal: journal, fiscal_year: fiscal_year, entry_date: cut_off, status: :draft,
                                               reference: "ACCR-#{accrual.id}", description: "#{accrual.accrual_type.humanize}: #{accrual.description}")
      debit_account, credit_account = accounts_for(accrual)
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: debit_account, debit: amount, credit: 0, label: accrual.description)
      Accounting::JournalEntryLine.create!(journal_entry: entry, account: credit_account, debit: 0, credit: amount, label: accrual.description)
      accrual.update!(journal_entry: entry)
    end
    ctx
  rescue StandardError => e
    ctx.tap { |c| c.fail!("Error: #{e.message}") }
  end

  def self.accounts_for(accrual)
    case accrual.accrual_type.to_sym
    when :deferred_charge, :accrued_income then [ accrual.accrual_account, accrual.pl_account ]
    else [ accrual.pl_account, accrual.accrual_account ]
    end
  end

  def self.refusal(accrual, fiscal_year, amount)
    return "This regularization is already booked." if accrual.booked?
    return I18n.t("accounting.fixed_assets.errors.fiscal_year_closed") if fiscal_year.closed?

    "Nothing to book at the cut-off date (amount is zero)." unless amount.positive?
  end

  private_class_method :accounts_for, :refusal
end
