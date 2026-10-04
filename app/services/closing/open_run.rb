# Opens the guided closing of a fiscal year (F10): a run with its steps, all pending. One run at a time per year; a closed year is reopened, not run again.
# => ctx[:run] (the existing one when a run is already under way)
class Closing::OpenRun
  def self.call(fiscal_year:, user:)
    ctx = LightService::Context.make(run: nil)
    return ctx.tap { |c| c.fail!("The fiscal year #{fiscal_year.year} is closed: reopen it first.") } if fiscal_year.closed?

    existing = Accounting::ClosingRun.active.find_by(fiscal_year: fiscal_year)
    return ctx.tap { |c| c[:run] = existing; c.fail!("A closing is already under way for #{fiscal_year.year}.") } if existing

    ApplicationRecord.transaction do
      run = Accounting::ClosingRun.create!(fiscal_year: fiscal_year, opened_by: user, opened_at: Time.current, status: :draft)
      Closing::Registry.steps.each_with_index do |step, index|
        run.steps.create!(position: step.position || index + 1, code: step.code, title: step.title, kind: step.kind, blocking: step.blocking)
      end
      ctx[:run] = run
    end
    ctx
  end
end
