# F08: what the current user is told, in the application.
class Accounting::NotificationsController < ApplicationController
  before_action { require_feature!(:f08) }

  def index
    @notifications = Accounting::Notification.where(user: current_user, channel: :in_app).includes(:subject).order(id: :desc).limit(100)
  end

  def read
    notification = Accounting::Notification.where(user: current_user).find(params[:id])
    notification.read!
    redirect_to(target_of(notification) || accounting_notifications_path)
  end

  def read_all
    Accounting::Notification.where(user: current_user).unread.update_all(read_at: Time.current)
    redirect_to accounting_notifications_path, notice: t("accounting.tasks.all_read")
  end

  private

  def target_of(notification)
    subject = notification.subject
    task = subject.is_a?(Accounting::Task) ? subject : (subject.commentable if subject.respond_to?(:commentable) && subject.commentable.is_a?(Accounting::Task))
    accounting_task_path(task) if task
  end
end
