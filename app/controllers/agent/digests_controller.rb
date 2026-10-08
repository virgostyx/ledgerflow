# The summaries of a person (A10a): their own, never another's. Each point offers "Create a task" and "Ask the assistant", which are the person's actions: the summary changes nothing by itself.
class Agent::DigestsController < Agent::BaseController
  before_action :set_digest, only: %i[show create_task]

  def index
    @digests = Agent::Digest.where(user_id: current_user.id).recent.limit(60)
    @preference = Agent::DigestPreference.for(current_user)
  end

  def show
    @digest.read!
    Accounting::Notification.where(user: current_user, subject: @digest).unread.find_each(&:read!)
  end

  def create_task
    item = @digest.sections.flat_map { |section| section["items"] }.find { |row| row["key"] == params[:key].to_s } or return head :not_found
    task = Accounting::Task.new(title: item["text"].first(120), kind: :to_check, author: current_user, status: :open, description: "From the assistant's summary of #{@digest.local_date.iso8601}.")
    authorize task, :create?, policy_class: Accounting::TaskPolicy
    task.save!
    redirect_to accounting_task_path(task), notice: "Task created.", status: :see_other
  end

  private

  def set_digest = @digest = Agent::Digest.where(user_id: current_user.id).find(params[:id])
end
