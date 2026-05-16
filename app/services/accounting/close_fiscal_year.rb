class Accounting::CloseFiscalYear
  extend LightService::Organizer

  def self.call(fiscal_year:, closed_by:)
    if fiscal_year.closed?
      ctx = LightService::Context.make(fiscal_year: fiscal_year)
      ctx.fail!(I18n.t("accounting.fiscal_years.errors.already_closed"))
      return ctx
    end

    closing_journal = Accounting::Journal.where(journal_type: :misc, active: true).first
    result_account  = Accounting::Account.find_by(code: "699000")

    unless closing_journal && result_account
      ctx = LightService::Context.make(fiscal_year: fiscal_year)
      ctx.fail!(I18n.t("accounting.fiscal_years.errors.missing_setup"))
      return ctx
    end

    result = nil
    ApplicationRecord.transaction do
      result = with(
        fiscal_year:     fiscal_year,
        closed_by:       closed_by,
        closing_journal: closing_journal,
        result_account:  result_account
      ).reduce(
        Accounting::Actions::ValidateNoOpenEntries,
        Accounting::Actions::GenerateClosingEntry,
        Accounting::Actions::MarkFiscalYearClosed
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    ctx = LightService::Context.make(fiscal_year: fiscal_year)
    ctx.fail!("Error: #{e.message}")
    ctx
  end
end
