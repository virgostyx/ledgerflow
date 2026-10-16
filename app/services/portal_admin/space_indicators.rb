# B02c: what the firm reads at a glance about the portal of a company: how long clients take to answer, how many answer within a week, what waits and for how long, who does not come. Computed
# in SQL on the portal's tables.
class PortalAdmin::SpaceIndicators
  INACTIVE_AFTER = 30.days

  def self.call(entity:)
    id = entity.id
    average, rate = ApplicationRecord.connection.select_rows(ApplicationRecord.sanitize_sql_array([ <<~SQL, id ])).first
      SELECT AVG(EXTRACT(EPOCH FROM (a.answered_at - q.asked_at)) / 86400.0),
             100.0 * COUNT(*) FILTER (WHERE a.answered_at - q.asked_at <= interval '7 days') / NULLIF(COUNT(*), 0)
      FROM portal_answers a JOIN portal_questions q ON q.id = a.question_id WHERE q.entity_id = ?
    SQL
    { average_days_to_answer: average && BigDecimal(average.to_s).round(1), answered_within_7_days_rate: rate && BigDecimal(rate.to_s).round(1), waiting_by_age: waiting(id), inactive_people: inactive(id) }
  end

  def self.waiting(id)
    row = ApplicationRecord.connection.select_rows(ApplicationRecord.sanitize_sql_array([ <<~SQL, id ])).first
      SELECT COUNT(*) FILTER (WHERE asked_at > now() - interval '7 days'),
             COUNT(*) FILTER (WHERE asked_at <= now() - interval '7 days' AND asked_at > now() - interval '14 days'),
             COUNT(*) FILTER (WHERE asked_at <= now() - interval '14 days')
      FROM portal_questions WHERE entity_id = ? AND status = 'open'
    SQL
    { "0-7 days" => row[0].to_i, "8-14 days" => row[1].to_i, "over 14 days" => row[2].to_i }
  end

  # People with a right in force here who have not had a session for 30 days (or never).
  def self.inactive(id)
    seen = Portal::Session.where("last_seen_at > ?", Time.current - INACTIVE_AFTER).select(:portal_user_id)
    PortalUser.where(id: Portal::Grant.in_force.where(entity_id: id).select(:portal_user_id)).where.not(id: seen).order(:full_name).to_a
  end
  private_class_method :waiting, :inactive
end
