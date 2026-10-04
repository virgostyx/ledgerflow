# F07: the recurring journal entries: list (next due date, last run, status, preview of the twelve next), create, pause, resume, skip.
class Accounting::RecurringEntriesController < ApplicationController
  before_action :set_recurring, only: %i[edit update destroy pause resume skip approve_post]
  before_action -> { authorize Accounting::RecurringEntry, :index? }, except: :approve_post
  before_action -> { authorize Accounting::RecurringEntry, :approve_post? }, only: :approve_post

  def index
    @recurrings = Accounting::RecurringEntry.includes(entry_template: { lines: :account }).order(:name).to_a
    @last_runs = Accounting::RecurringRun.where(recurring_entry_id: @recurrings.map(&:id)).order(:due_on).index_by(&:recurring_entry_id)
    @previews = @recurrings.to_h { |r| [ r.id, r.upcoming_dates(12).map { |date| [ date, r.forecast_amount(date) ] } ] }
    @monthly = @previews.values.flatten(1).group_by { |date, _| date.beginning_of_month }.transform_values { |rows| rows.sum { |_, amount| amount || 0 } }.sort.first(12)
  end

  def new
    @recurring = Accounting::RecurringEntry.new(starts_on: Date.current, day_of_month: 1)
  end

  def create
    @recurring = Accounting::RecurringEntry.new(recurring_params.merge(created_by: current_user))
    if @recurring.save
      redirect_to accounting_recurring_entries_path, notice: "Recurring entry #{@recurring.name} created: next due #{l @recurring.next_due_on}"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @recurring.update(recurring_params)
      redirect_to accounting_recurring_entries_path, notice: "Recurring entry #{@recurring.name} updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @recurring.destroy!
    redirect_to accounting_recurring_entries_path, notice: "Recurring entry deleted: the entries it made are kept"
  end

  def pause
    @recurring.paused!
    audit("recurring_paused")
    redirect_to accounting_recurring_entries_path, notice: "#{@recurring.name} paused"
  end

  def resume
    @recurring.update_columns(status: Accounting::RecurringEntry.statuses[:active], blocked_reason: nil, updated_at: Time.current)
    audit("recurring_resumed")
    redirect_to accounting_recurring_entries_path, notice: "#{@recurring.name} resumed"
  end

  def skip
    result = Accounting::SkipRecurringOccurrence.call(recurring: @recurring, user: current_user)
    redirect_to accounting_recurring_entries_path, result.success? ? { notice: "Due date skipped" } : { alert: result.message }
  end

  def approve_post
    result = Accounting::ApproveRecurringPost.call(recurring: @recurring, user: current_user)
    redirect_to accounting_recurring_entries_path, result.success? ? { notice: "#{@recurring.name} will post by itself" } : { alert: result.message }
  end

  private

  def set_recurring = @recurring = Accounting::RecurringEntry.find(params[:id])

  def audit(action) = Accounting::AuditLog.record!(auditable: @recurring, action: action, user: current_user)

  def recurring_params
    params.require(:accounting_recurring_entry).permit(:name, :entry_template_id, :frequency, :day_of_month, :starts_on, :ends_on, :max_occurrences,
                                                       :lead_days, :base_amount, :indexation_percent, :feeds_cash_forecast)
  end
end
