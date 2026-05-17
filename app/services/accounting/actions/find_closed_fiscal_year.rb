class Accounting::Actions::FindClosedFiscalYear
  extend LightService::Action

  expects :new_fiscal_year
  promises :previous_fiscal_year

  executed do |ctx|
    ctx[:previous_fiscal_year] = Accounting::FiscalYear
      .where(status: :closed)
      .where(end_date: ...(ctx.new_fiscal_year.start_date))
      .order(end_date: :desc)
      .first
  end
end
