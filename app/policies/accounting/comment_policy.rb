# Comments (F08): written by those who may comment (`comments.write`) on what they see; edited by their author for fifteen minutes; hidden by their
# author or by whoever manages tasks. Never deleted.
class Accounting::CommentPolicy < ApplicationPolicy
  def create? = can?("comments.write") && sees_subject?
  def edit?   = create? && record.respond_to?(:editable_by?) && record.editable_by?(user)
  def hide?   = sees_subject? && (record.author_id == user&.id || can?("tasks.manage"))
  def resolve? = create?

  private

  # What the comment is about, seen as such (a task as the list of tasks says); for anything else (the policy asked about the class), the right alone decides.
  def sees_subject?
    return true unless record.respond_to?(:commentable) && record.commentable

    Accounting::TaskTargets.visible_commentable?(user, record.commentable)
  end
end
