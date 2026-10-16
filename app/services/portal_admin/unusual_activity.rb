# B02a: what looks odd in the last day of a company's portal: a burst of downloads, attempts at objects outside the scope, repeated failed sign-ins.
class PortalAdmin::UnusualActivity
  BURST = { count: 20, window: 10.minutes }.freeze
  FAILURES = 5
  LOOKBACK = 1.day

  Finding = Struct.new(:person, :text, keyword_init: true)

  def self.call(entity:)
    events = PortalAdmin::ActivityFeed.call(entity: entity).where("occurred_at > ?", LOOKBACK.ago)
    findings = []
    events.where(action: "publication_downloaded").group(:portal_user_id).having("count(*) >= ?", BURST[:count]).count.each_key do |user_id|
      times = events.where(action: "publication_downloaded", portal_user_id: user_id).order(:occurred_at).pluck(:occurred_at)
      next unless times.each_cons(BURST[:count]).any? { |batch| batch.last - batch.first <= BURST[:window] }

      findings << Finding.new(person: PortalUser.find(user_id), text: "#{BURST[:count]} or more downloads in #{BURST[:window].in_minutes.to_i} minutes")
    end
    events.where(action: "out_of_scope_attempt").group(:portal_user_id).count.each do |user_id, n|
      findings << Finding.new(person: PortalUser.find(user_id), text: "#{n} attempt(s) at objects outside their scope")
    end
    events.where(action: "sign_in_failed").where.not(portal_user_id: nil).group(:portal_user_id).having("count(*) >= ?", FAILURES).count.each do |user_id, n|
      findings << Finding.new(person: PortalUser.find(user_id), text: "#{n} failed sign-ins")
    end
    findings
  end
end
