# B02c: checks a proof of approval on its own: the hash of the evidence, the manifest against the files of the publication (frozen), and the signature against the published keys (a key that was
# retired still verifies). Anything that fails is named. A proof that is not sealed yet says so.
class PortalAdmin::VerifyApproval
  Result = Struct.new(:problems, keyword_init: true) do
    def valid? = problems.empty?
  end

  def self.call(approval)
    problems = []
    evidence = approval.evidence
    problems << "the evidence was altered: its hash is not the one recorded" unless Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(evidence)) == approval.evidence_hash
    problems << "the manifest of the evidence is not the one recorded" unless Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(evidence["manifest"])) == approval.manifest_hash
    problems.concat(files_problems(approval, evidence["manifest"]))
    if approval.sealed?
      message = PortalAdmin::SealApprovals.message(approval)
      problems << "the signature does not verify with key #{approval.seal_key_id}" unless Ledger::SigningKeys.verify(approval.seal_key_id, message, approval.seal_signature)
    else
      problems << "the proof is not sealed yet"
    end
    Result.new(problems: problems)
  end

  # What was approved is what is published: each file of the manifest is still there with the same fingerprint, and nothing else.
  def self.files_problems(approval, manifest)
    current = approval.publication.files.map { |f| { "filename" => f.filename, "sha256" => f.sha256, "byte_size" => f.byte_size } }
    current == manifest ? [] : [ "the files of the publication no longer match the manifest that was approved" ]
  end
  private_class_method :files_problems
end
