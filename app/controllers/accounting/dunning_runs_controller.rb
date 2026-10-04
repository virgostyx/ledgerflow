# F09: the runs of customer reminders: prepare one from the open lines, look at it, validate and send it. Nothing is sent before `send_run`.
class Accounting::DunningRunsController < ApplicationController
  before_action { require_feature!(:f09) }

  def index
    authorize Accounting::DunningRun
    @pagy, @runs = pagy(Accounting::DunningRun.includes(:created_by, :items).order(id: :desc))
    @refused = Array(flash[:refused])
  end

  def show
    @run = Accounting::DunningRun.find(params[:id])
    authorize @run
    @items = @run.items.includes(:partner)
  end

  def create
    authorize Accounting::DunningRun
    result = Accounting::PrepareDunningRun.call(user: current_user)
    if result.success?
      flash[:refused] = refused_for_flash(result[:refused]) if result[:refused].any?
      redirect_to accounting_dunning_run_path(result[:run]), notice: t("accounting.dunning.prepared", count: result[:run].items.size)
    else
      flash[:refused] = refused_for_flash(result[:refused])
      redirect_to accounting_dunning_runs_path, alert: result.message
    end
  end

  def send_run
    run = Accounting::DunningRun.find(params[:id])
    authorize run, :send_run?
    result = Accounting::SendDunningRun.call(run: run, user: current_user)
    if result.failure?
      redirect_to accounting_dunning_run_path(run), alert: result.message
    else
      queued = run.items.queued.count
      flash[:notice] = t("accounting.dunning.queued", count: queued) if queued.positive?
      flash[:alert]  = result[:blocked].map { |b| "#{b[:item].partner.name}: #{b[:reason]}" }.join(" ") if result[:blocked].any?
      redirect_to accounting_dunning_run_path(run)
    end
  end

  private

  def refused_for_flash(refused) = refused.map { |r| [ r[:partner].name, r[:item].dunning_run_id ] }
end
