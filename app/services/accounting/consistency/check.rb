# Base class of an automatic consistency check (R19, docs/dev/reports/spec.md §13). A check is one class in
# `consistency/checks/`, named after its id (C01UnbalancedEntry); the runner discovers it by scanning that
# directory, so adding a check never touches the orchestrator. `call` returns findings built with `finding`;
# the fingerprint hashes the check id, the subject and the data that make the anomaly what it is, so a change
# of that data (a different amount, another gap) is a new anomaly again.
class Accounting::Consistency::Check
  Finding = Struct.new(:check_id, :severity, :subject_type, :subject_id, :message, :data, :fingerprint, keyword_init: true)

  class_attribute :check_id, :severity, :title, instance_accessor: false

  CHECKS_DIR = File.expand_path("checks", __dir__)

  def self.registry
    Dir[File.join(CHECKS_DIR, "*.rb")].sort.map { |file| "Accounting::Consistency::Checks::#{File.basename(file, '.rb').camelize}".constantize }
  end

  # `fiscal_year`: the one year to look at (the closing of F10 checks the year it closes, not the next one that has not received its opening entry yet).
  def initialize(fiscal_year: nil)
    @fiscal_year = fiscal_year
  end

  def call = raise(NotImplementedError)

  private

  # Fiscal years still open to change: closed years are frozen. Only the one asked for, when one is.
  def fiscal_years = @fiscal_year ? Accounting::FiscalYear.where(id: @fiscal_year.id) : Accounting::FiscalYear.where.not(status: Accounting::FiscalYear.statuses[:closed])

  def finding(subject:, message:, **data)
    subject_type = subject.is_a?(Array) ? subject.first : subject.class.name
    subject_id   = subject.is_a?(Array) ? subject.last : subject.id
    data = data.transform_values { |v| v.is_a?(BigDecimal) ? v.to_s("F") : v }
    fingerprint = Digest::SHA256.hexdigest([ self.class.check_id, subject_type, subject_id, JSON.generate(data.sort.to_h) ].join("|"))
    Finding.new(check_id: self.class.check_id, severity: self.class.severity, subject_type: subject_type, subject_id: subject_id,
                message: message, data: data, fingerprint: fingerprint)
  end
end
