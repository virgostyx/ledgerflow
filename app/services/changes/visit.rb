# B03b: the last visit of a person to the report of changes, only to propose T1. A company can switch it off (`track_visits`); the person erases theirs.
module Changes::Visit
  def self.record(user)
    return unless ActsAsTenant.current_tenant.track_visits

    visit = Accounting::UserVisit.find_or_initialize_by(user_id: user.id)
    visit.update!(visited_at: Time.current)
  end

  def self.last(user) = Accounting::UserVisit.find_by(user_id: user.id)&.visited_at

  def self.erase(user) = Accounting::UserVisit.where(user_id: user.id).delete_all
end
