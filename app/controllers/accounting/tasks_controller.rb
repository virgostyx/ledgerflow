# F08: « Mes tâches » and « Toutes les tâches », made from any screen (the target is prefilled), with the thread of comments of each.
class Accounting::TasksController < ApplicationController
  before_action { require_feature!(:f08) }
  before_action :set_task, only: %i[show edit update external_link revoke_external_link]

  def index
    authorize Accounting::Task
    @scope = params[:scope] == "all" ? "all" : "mine"
    tasks = policy_scope(Accounting::Task).includes(:assignee, :author, :target)
    tasks = tasks.where(assignee_id: current_user.id).open_ones if @scope == "mine"
    tasks = filter(tasks)
    @pagy, @tasks = pagy(tasks.order(Arel.sql("due_on IS NULL"), :due_on, id: :desc))
    ActiveRecord::Associations::Preloader.new(records: @tasks.map(&:target).grep(Accounting::JournalEntryLine), associations: :journal_entry).call # their label names the entry
    @assignees = User.where(id: UserEntity.current.where(entity_id: ActsAsTenant.current_tenant.id).select(:user_id)).order(:full_name)
  end

  def new
    @task = Accounting::Task.new(target: find_target, anomaly_fingerprint: params[:anomaly_fingerprint].presence, title: params[:title], kind: kind_param || :other,
                                 due_on: nil, priority: :normal)
    authorize @task, :create?
    load_assignees
  end

  def create
    result = Accounting::CreateTask.call(user: current_user, **task_params, target: find_target, anomaly_fingerprint: params.dig(:accounting_task, :anomaly_fingerprint).presence)
    if result.success?
      redirect_to accounting_task_path(result[:task]), notice: t("accounting.tasks.created")
    else
      @task = Accounting::Task.new(task_params.merge(target: find_target))
      authorize @task, :create?
      load_assignees
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  end

  def show
    authorize @task
    @roots = @task.comments.where(parent_id: nil).includes(:author, replies: :author)
  end

  def edit
    authorize @task, :update?
    load_assignees
  end

  def update
    authorize @task, :update?
    result = Accounting::UpdateTask.call(task: @task, user: current_user, **task_params)
    if result.success?
      redirect_to accounting_task_path(@task), notice: t("accounting.tasks.updated")
    else
      load_assignees
      flash.now[:alert] = result.message
      render :edit, status: :unprocessable_content
    end
  end

  # A question to a third party: the link they answer through (shown on the task, for the person to send as they see fit).
  def external_link
    authorize @task, :update?
    result = Accounting::IssueExternalLink.call(task: @task, user: current_user, question: params[:question], days: params[:days])
    redirect_to accounting_task_path(@task), result.success? ? { notice: t("accounting.tasks.link_issued") } : { alert: result.message }
  end

  def revoke_external_link
    authorize @task, :update?
    Accounting::RevokeExternalLink.call(task: @task, user: current_user)
    redirect_to accounting_task_path(@task), notice: t("accounting.tasks.link_revoked")
  end

  private

  def set_task = @task = policy_scope(Accounting::Task).find(params[:id])

  def task_params
    params.require(:accounting_task).permit(:title, :description, :status, :priority, :kind, :assignee_id, :due_on).to_h.symbolize_keys.compact_blank
  end

  def kind_param = (Accounting::Task.kinds.key?(params[:kind].to_s) ? params[:kind] : nil)

  # The thing a task is made about, from the screen it is made from: of a known type, of this entity, never one that cannot be seen.
  def find_target
    type = params[:target_type].presence || params.dig(:accounting_task, :target_type).presence
    id = params[:target_id].presence || params.dig(:accounting_task, :target_id).presence
    return unless type && id && Accounting::TaskTargets::TYPES.include?(type)

    type.constantize.find_by(id: id)
  end

  def load_assignees
    @assignees = User.where(id: UserEntity.current.where(entity_id: ActsAsTenant.current_tenant.id).select(:user_id)).order(:full_name)
  end

  def filter(tasks)
    tasks = tasks.where(status: params[:status]) if Accounting::Task.statuses.key?(params[:status].to_s)
    tasks = tasks.where(kind: params[:kind]) if kind_param
    tasks = tasks.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    tasks = tasks.where(anomaly_fingerprint: params[:anomaly_fingerprint]) if params[:anomaly_fingerprint].present?
    tasks = tasks.where(target_type: params[:target_type], target_id: params[:target_id].presence) if Accounting::TaskTargets::TYPES.include?(params[:target_type].to_s)
    case params[:due]
    when "overdue" then tasks.overdue
    when "week" then tasks.open_ones.where(due_on: Date.current..Date.current + 7)
    else tasks
    end
  end
end
