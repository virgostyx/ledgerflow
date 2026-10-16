# B02b: four numbers on what the clients send, each computed in SQL: the average delay from a bank movement to the deposit of its document (days), the share of sends "to complete", the share of the
# documents asked for that came by the date asked (among those due), and the part of the portal in the documents that came from outside (portal / (portal + e-mail), over a year). nil when there is nothing to measure.
class PortalAdmin::UploadIndicators
  def self.call(entity:)
    new(entity).call
  end

  def initialize(entity)
    @id = entity.id
  end

  def call
    { delay_days: delay, to_complete_rate: to_complete, in_time_rate: in_time, portal_share: portal_share }
  end

  private

  def one(sql, *binds) = ApplicationRecord.connection.select_value(ApplicationRecord.sanitize_sql_array([ sql, *binds ]))
  def number(value, places) = value && BigDecimal(value.to_s).round(places)

  def delay
    number(one(<<~SQL, @id), 1)
      SELECT AVG(u.received_at::date - t.transaction_date)
      FROM portal_document_request_lines l
      JOIN portal_uploads u ON u.request_line_id = l.id AND u.received_at IS NOT NULL
      JOIN accounting_bank_transactions t ON t.id = l.bank_transaction_id
      WHERE l.entity_id = ? AND l.state = 'provided'
    SQL
  end

  def to_complete
    number(one("SELECT 100.0 * COUNT(*) FILTER (WHERE status = 'to_complete' OR progress = 'to_complete') / NULLIF(COUNT(*), 0) FROM portal_uploads WHERE entity_id = ? AND status IN ('accepted', 'to_complete')", @id), 1)
  end

  def in_time
    number(one(<<~SQL, @id, Date.current), 1)
      SELECT 100.0 * COUNT(*) FILTER (WHERE l.state = 'provided' AND u.received_at::date <= r.due_on) / NULLIF(COUNT(*), 0)
      FROM portal_document_request_lines l
      JOIN portal_document_requests r ON r.id = l.request_id
      LEFT JOIN portal_uploads u ON u.request_line_id = l.id AND u.received_at IS NOT NULL
      WHERE l.entity_id = ? AND r.due_on IS NOT NULL AND (l.state = 'provided' OR r.due_on < ?) AND l.state <> 'withdrawn'
    SQL
  end

  def portal_share
    number(one("SELECT 100.0 * COUNT(*) FILTER (WHERE origin = ?) / NULLIF(COUNT(*), 0) FROM accounting_documents WHERE entity_id = ? AND origin IN (?, ?) AND created_at > ?",
               Accounting::Document.origins.fetch("portal"), @id, Accounting::Document.origins.fetch("portal"), Accounting::Document.origins.fetch("email"), 1.year.ago), 1)
  end
end
