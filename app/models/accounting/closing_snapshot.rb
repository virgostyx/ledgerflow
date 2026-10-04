# The state of the books when a year closed (F10): the trial balance, the balance sheet and the income statement as JSON, and its SHA-256, so that
# reading it again gives the same fingerprint (a snapshot that changed is a snapshot that was tampered with).
class Accounting::ClosingSnapshot < ApplicationRecord
  self.table_name = "closing_snapshots"

  acts_as_tenant :entity

  belongs_to :run, class_name: "Accounting::ClosingRun", foreign_key: :closing_run_id, inverse_of: :snapshot

  validates :content, :sha256, presence: true

  # The fingerprint of a content: SHA-256 of its canonical JSON (keys sorted, whatever order the database returns them in).
  def self.fingerprint(content) = Digest::SHA256.hexdigest(JSON.generate(canonical(content.as_json)))

  def self.canonical(value)
    case value
    when Hash then value.sort.to_h { |k, v| [ k.to_s, canonical(v) ] }
    when Array then value.map { |v| canonical(v) }
    else value
    end
  end

  def intact? = sha256 == self.class.fingerprint(content)
end
