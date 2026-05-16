class Accounting::Actions::MarkFiscalYearClosed
  extend LightService::Action

  expects :fiscal_year, :closed_by

  executed do |ctx|
    ctx.fiscal_year.update!(
      status:        :closed,
      closed_at:     Time.current,
      closed_by_id:  ctx.closed_by.id
    )
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!("Close error: #{e.message}")
  end
end
