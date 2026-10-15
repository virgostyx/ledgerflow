# B03c: the invariants of the specification (I1 to I17) that can be replayed on the books as they are, and what they say. The others are properties of the way the code is
# written, proved by the tests (random sequences), not replayable on a company's data: they are reported as such, never as holding.
#
# => { "I1" => { "status" => "holds" | "fails" | "not_replayed", "detail" => ... }, ... }
module Integrity::Invariants
  ALL = (1..17).map { |n| "I#{n}" }.freeze

  # The checks of R19 that stand for an invariant, and which finding says which.
  CHECKS = {
    "I1" => [ Accounting::Consistency::Checks::C01UnbalancedEntry, nil ],
    "I2" => [ Accounting::Consistency::Checks::C11Invariants, "I2" ],
    "I6" => [ Accounting::Consistency::Checks::C11Invariants, "I6" ],
    "I7" => [ Accounting::Consistency::Checks::C11Invariants, "I7" ],
    "I10" => [ Accounting::Consistency::Checks::C16FixedAssetRegister, nil ],
    "I11" => [ Accounting::Consistency::Checks::C11Invariants, "I11" ],
    "I14" => [ Accounting::Consistency::Checks::C21ChangesClosing, nil ]
  }.freeze

  def self.call(anchors: Ledger::AnchorChain.verify(ActsAsTenant.current_tenant))
    findings = CHECKS.values.map(&:first).uniq.to_h { |check| [ check, check.new.call ] }
    ALL.to_h do |id|
      [ id, result(id, findings, anchors) ]
    end
  end

  def self.result(id, findings, anchors)
    return { "status" => anchors.intact? ? "holds" : "fails", "detail" => (anchors.reason unless anchors.intact?) }.compact if id == "I17"

    check, invariant = CHECKS[id]
    return { "status" => "not_replayed" } unless check

    broken = findings.fetch(check).select { |finding| invariant.nil? || finding.data[:invariant] == invariant }
    broken.empty? ? { "status" => "holds" } : { "status" => "fails", "detail" => broken.first.message }
  end
  private_class_method :result
end
