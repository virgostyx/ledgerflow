# Step 1 of the closing (F10): the preparation. The next fiscal year exists; if not, it is created on request (the same length as this one, waiting: only one
# year is open at a time, and this one is not closed yet). A year that is already closed has nothing to prepare.
class Closing::Steps::Preparation < Closing::Step
  self.position = 1
  self.code     = "preparation"
  self.title    = "Preparation"
  self.kind     = :action
  self.blocking = true

  def evaluate
    return blocked("reason" => "closed") if fiscal_year.closed?

    following ? ok("next_fiscal_year_id" => following.id) : pending("next_year_missing" => true)
  end

  def perform(user:)
    ctx = LightService::Context.make(fiscal_year: nil)
    return ctx.tap { |c| c.fail!("The fiscal year #{fiscal_year.year} is closed.") } if fiscal_year.closed?
    return ctx.tap { |c| c[:fiscal_year] = following } if following

    months = ((year_end.year * 12 + year_end.month) - (fiscal_year.start_date.year * 12 + fiscal_year.start_date.month)) + 1
    start = year_end + 1
    ctx[:fiscal_year] = Accounting::FiscalYear.create!(year: fiscal_year.year + 1, start_date: start, end_date: (start >> months) - 1, status: :pre_closing)
    Accounting::AuditLog.record!(auditable: run, action: "closing_next_year_created", user: user, payload: { fiscal_year_id: ctx[:fiscal_year].id, year: ctx[:fiscal_year].year })
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
    ctx
  end

  private

  def following = Accounting::FiscalYear.find_by(start_date: year_end + 1)
end
