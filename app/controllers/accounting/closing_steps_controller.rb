# F10: what a person does on a step of the closing: the action, the acknowledgement of a warning, the skip of a step that does not block, the confirmation of
# a manual step, a comment of the analytical review. Each is a service; this only routes and says what happened.
class Accounting::ClosingStepsController < ApplicationController
  before_action { require_feature!(:f10) }
  before_action :set_run_and_step

  def perform
    authorize @run, :update?
    result = Closing::PerformStep.call(run: @run, code: @step.code, user: current_user)
    back(result, "Done: #{@step.title}.")
  end

  def acknowledge
    authorize @run, :update?
    back Closing::AcknowledgeStep.call(step: @step, user: current_user, comment: params[:comment]), "Acknowledged."
  end

  def skip
    authorize @run, :update?
    back Closing::SkipStep.call(step: @step, user: current_user, reason: params[:reason]), "Skipped."
  end

  def confirm
    authorize @run, :update?
    back Closing::ConfirmStep.call(step: @step, user: current_user, comment: params[:comment]), "Confirmed."
  end

  def comment
    authorize @run, :update?
    back Closing::Steps::AnalyticalReview.new(@run).comment(user: current_user, code: params[:heading], text: params[:text]), "Comment saved."
  end

  private

  def set_run_and_step
    @run = Accounting::ClosingRun.find(params[:closing_run_id])
    @step = @run.steps.find_by!(code: params[:code])
  end

  def back(result, notice)
    redirect_to accounting_closing_run_path(@run, anchor: "step-#{@step.code}"), (result.success? ? { notice: notice } : { alert: result.message })
  end
end
