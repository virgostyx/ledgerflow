module Accounting::Immutable
  extend ActiveSupport::Concern

  included do
    before_update  :prevent_update_if_posted
    before_destroy :prevent_destroy_if_posted
  end

  private

  def prevent_update_if_posted
    return unless respond_to?(:status)
    # Use DB value — in-memory status is already set by AASM before save
    return unless status_in_database == "posted"
    # Allow the reverse! transition (posted → reversed)
    return if will_save_change_to_status?(to: "reversed")

    raise Accounting::ImmutableRecordError,
          "#{self.class.name} ##{id} is posted and cannot be modified."
  end

  def prevent_destroy_if_posted
    return unless respond_to?(:status)
    return unless status_in_database == "posted"

    raise Accounting::ImmutableRecordError,
          "#{self.class.name} ##{id} is posted and cannot be deleted."
  end
end
