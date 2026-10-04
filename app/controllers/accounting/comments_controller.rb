# F08: the comments of a thread: write, edit (the author, fifteen minutes), hide (never deleted), settle.
class Accounting::CommentsController < ApplicationController
  before_action { require_feature!(:f08) }
  before_action :set_comment, only: %i[update hide resolve reopen]

  def create
    result = Accounting::AddComment.call(commentable: commentable, user: current_user, body: params[:body], parent: parent)
    if result.success?
      ignored = result[:ignored_mentions]
      redirect_back_to(commentable, notice: (ignored.any? ? t("accounting.tasks.mentions_ignored", names: ignored.map { |n| "@#{n}" }.to_sentence) : t("accounting.tasks.commented")))
    else
      redirect_back_to(commentable, alert: result.message)
    end
  end

  def update
    result = Accounting::EditComment.call(comment: @comment, user: current_user, body: params[:body])
    redirect_back_to(@comment.commentable, result.success? ? { notice: t("accounting.tasks.comment_updated") } : { alert: result.message })
  end

  def hide
    result = Accounting::HideComment.call(comment: @comment, user: current_user)
    redirect_back_to(@comment.commentable, result.success? ? { notice: t("accounting.tasks.comment_hidden") } : { alert: result.message })
  end

  def resolve
    Accounting::ResolveComment.call(comment: @comment, user: current_user, resolved: true)
    redirect_back_to(@comment.commentable, notice: t("accounting.tasks.comment_resolved"))
  end

  def reopen
    Accounting::ResolveComment.call(comment: @comment, user: current_user, resolved: false)
    redirect_back_to(@comment.commentable, notice: t("accounting.tasks.comment_reopened"))
  end

  private

  def set_comment = @comment = Accounting::Comment.find(params[:id])

  # A task or a thing of a known type, of this entity.
  def commentable
    @commentable ||= begin
      type = params[:commentable_type].to_s
      allowed = Accounting::TaskTargets::TYPES + [ "Accounting::Task" ]
      allowed.include?(type) ? type.constantize.find(params[:commentable_id]) : (raise ActiveRecord::RecordNotFound)
    end
  end

  def parent = (Accounting::Comment.find_by(id: params[:parent_id]) if params[:parent_id].present?)

  def redirect_back_to(record, flash = {})
    redirect_back fallback_location: (record.is_a?(Accounting::Task) ? accounting_task_path(record) : accounting_tasks_path), **flash
  end
end
