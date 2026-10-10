# The figures of the approval dashboard (B01a §4 "Tableau des approbations"): for the requests submitted in a period, where they ended up, the refusal rate
# and the mean time to an approval; what waits now and is late; and by approver and by supplier. Everything is added up by the database.
# Late has two senses, both shown: past the service time of the level (the circuit's own deadline), and the invoice itself past its due date.
# How long an approver took is the time since the request last moved (its submission, or the previous decision on it), at the moment they decided.
class Approvals::Dashboard
  Result = Struct.new(:from, :to, :submitted, :by_status, :pending_now, :refusal_rate, :mean_hours_to_approval, :late_by_service_time, :late_by_due_date,
                      :by_approver, :by_supplier, keyword_init: true)
  ApproverRow = Struct.new(:user, :decisions, :approved, :rejected, :changes_requested, :transferred, :mean_hours, :waiting_now, keyword_init: true)
  SupplierRow = Struct.new(:partner, :requests, :approved, :refused, :pending, :mean_hours_to_approval, keyword_init: true)

  STATUS = Approvals::Request.statuses.freeze
  DECISION = Approvals::Decision.decisions.freeze

  def self.call(from:, to:) = new(from, to).call

  def initialize(from, to)
    @from = from
    @to = to
    @range = from.beginning_of_day..to.end_of_day
  end

  def call
    counts = requests.group(:status).count
    Result.new(from: @from, to: @to, submitted: counts.values.sum, by_status: counts, pending_now: pending.count, refusal_rate: refusal_rate(counts),
               mean_hours_to_approval: hours(requests.approved.average(Arel.sql(WAITED))), late_by_service_time: late_by_service_time, late_by_due_date: late_by_due_date,
               by_approver: by_approver, by_supplier: by_supplier)
  end

  private

  WAITED = "EXTRACT(EPOCH FROM (approval_requests.decided_at - approval_requests.submitted_at))".freeze

  def requests = Approvals::Request.where(submitted_at: @range)

  def pending = Approvals::Request.pending

  def hours(seconds) = seconds && (BigDecimal(seconds.to_s) / 3600).round(2)

  # Among the requests decided (approved, refused, sent back for changes): the share that was refused or sent back.
  def refusal_rate(counts)
    refused = counts.fetch("rejected", 0) + counts.fetch("changes_requested", 0)
    decided = refused + counts.fetch("approved", 0)
    BigDecimal(refused) / decided if decided.positive?
  end

  def late_by_service_time
    pending.joins("JOIN approval_steps s ON s.policy_id = approval_requests.policy_id AND s.position = approval_requests.current_step")
           .where("s.service_hours IS NOT NULL AND approval_requests.step_started_at + s.service_hours * INTERVAL '1 hour' < ?", Time.current).count
  end

  def late_by_due_date
    pending.where(subject_type: "Accounting::Invoice").joins("JOIN accounting_invoices i ON i.id = approval_requests.subject_id").where("i.due_date < ?", Date.current).count
  end

  def by_approver
    rows = select_all(<<~SQL, entity: ActsAsTenant.current_tenant.id, from: @range.begin, to: @range.end)
      SELECT approver_id, COUNT(*) AS decisions,
             COUNT(*) FILTER (WHERE decision = #{DECISION['approved']}) AS approved, COUNT(*) FILTER (WHERE decision = #{DECISION['rejected']}) AS rejected,
             COUNT(*) FILTER (WHERE decision = #{DECISION['changes_requested']}) AS changes_requested, COUNT(*) FILTER (WHERE decision = #{DECISION['transferred']}) AS transferred,
             AVG(waited) AS waited
      FROM (
        SELECT d.approver_id, d.decision, d.decided_at,
               EXTRACT(EPOCH FROM (d.decided_at - COALESCE(LAG(d.decided_at) OVER (PARTITION BY d.request_id ORDER BY d.decided_at, d.id), r.submitted_at))) AS waited
        FROM approval_decisions d JOIN approval_requests r ON r.id = d.request_id
        WHERE d.entity_id = :entity
      ) timed
      WHERE decided_at BETWEEN :from AND :to
      GROUP BY approver_id
    SQL
    waiting = waiting_now
    users = User.where(id: rows.map { |r| r["approver_id"] } | waiting.keys).index_by(&:id)
    figures = rows.index_by { |r| r["approver_id"] }
    (figures.keys | waiting.keys).map do |id|
      row = figures[id] || {}
      ApproverRow.new(user: users.fetch(id), decisions: row.fetch("decisions", 0), approved: row.fetch("approved", 0), rejected: row.fetch("rejected", 0),
                      changes_requested: row.fetch("changes_requested", 0), transferred: row.fetch("transferred", 0), mean_hours: hours(row["waited"]), waiting_now: waiting.fetch(id, 0))
    end.sort_by { |row| [ -row.decisions, row.user.full_name.to_s ] }
  end

  # { user_id => how many requests wait for them now }
  def waiting_now
    directory = Approvals::Directory.new
    pending.includes(policy: :steps).each_with_object(Hash.new(0)) do |request, counts|
      Approvals::Approvers.for(request, directory).each_key { |id| counts[id] += 1 }
    end
  end

  def by_supplier
    rows = select_all(<<~SQL, from: @range.begin, to: @range.end, entity: ActsAsTenant.current_tenant.id)
      SELECT i.partner_id, COUNT(*) AS requests,
             COUNT(*) FILTER (WHERE r.status = #{STATUS['approved']}) AS approved,
             COUNT(*) FILTER (WHERE r.status IN (#{STATUS['rejected']}, #{STATUS['changes_requested']})) AS refused,
             COUNT(*) FILTER (WHERE r.status = #{STATUS['pending']}) AS pending,
             AVG(EXTRACT(EPOCH FROM (r.decided_at - r.submitted_at))) FILTER (WHERE r.status = #{STATUS['approved']}) AS waited
      FROM approval_requests r JOIN accounting_invoices i ON i.id = r.subject_id AND r.subject_type = 'Accounting::Invoice'
      WHERE r.entity_id = :entity AND r.submitted_at BETWEEN :from AND :to
      GROUP BY i.partner_id
    SQL
    partners = Accounting::Partner.where(id: rows.map { |r| r["partner_id"] }).index_by(&:id)
    rows.map do |r|
      SupplierRow.new(partner: partners.fetch(r["partner_id"]), requests: r["requests"], approved: r["approved"], refused: r["refused"], pending: r["pending"], mean_hours_to_approval: hours(r["waited"]))
    end.sort_by { |row| [ -row.requests, row.partner.name ] }
  end

  def select_all(sql, binds)
    ApplicationRecord.connection.select_all(ApplicationRecord.sanitize_sql([ sql, binds ])).to_a
  end
end
