# F11: until the accountant validates another treatment, an unrealized exchange gain is not booked: that is what was decided with the first
# revaluation (docs/dev/reports/QUESTIONS.md, 2026-10-01). Deferring or recognizing it are choices to make per entity.
class DefaultUnrealizedGainToIgnore < ActiveRecord::Migration[8.1]
  def change
    change_column_default :entities, :fx_unrealized_gain, from: 0, to: 2
  end
end
