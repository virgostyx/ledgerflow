# F09: a dispute or a promise of payment on a customer line, entered from the reminder that shows it (`item_id` brings the person back to it).
class Accounting::DunningLinesController < ApplicationController
  before_action { require_feature!(:f09) }
  before_action :set_line

  def dispute
    authorize Accounting::DunningRun, :update?
    done Accounting::SetLineDispute.call(line: @line, disputed: ActiveModel::Type::Boolean.new.cast(params[:disputed]), user: current_user)
  end

  def promise
    authorize Accounting::DunningRun, :update?
    done Accounting::SetPaymentPromise.call(line: @line, on: params[:payment_promised_on].presence&.to_date, user: current_user)
  end

  private

  def set_line = @line = Accounting::JournalEntryLine.find(params[:id])

  def done(result)
    target = params[:item_id].present? ? accounting_dunning_item_path(params[:item_id]) : accounting_dunning_runs_path
    redirect_to target, (result.success? ? { notice: t("accounting.dunning.line_updated") } : { alert: result.message })
  end
end
