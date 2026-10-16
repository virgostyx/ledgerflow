# B02c: the client's decision on a publication, and its proof: who, what (the publication and the fingerprint of the manifest of its files), when, from where, how the second factor was given and the
# text shown. `evidence_hash` is the SHA-256 of the evidence in canonical JSON (RFC 8785); the firm's side seals it with the signing key of B03c, which the portal never touches. Immutable.
class Portal::Approval < ApplicationRecord
  DECISIONS = %w[approved approved_with_remarks refused].freeze

  belongs_to :publication, class_name: "Portal::Publication"
  belongs_to :portal_user

  validates :decision, inclusion: { in: DECISIONS }
  scope :active, -> { where(status: "active") }

  def sealed? = sealed_at.present?
  def approving? = decision != "refused"

  # Writes the decision with its proof. `session` gives the way and the moment of the second factor.
  def self.record!(publication:, person:, session:, decision:, comment:, ip:, user_agent:, locale:)
    files = publication.files.to_a
    manifest = files.map { |f| { "filename" => f.filename, "sha256" => f.sha256, "byte_size" => f.byte_size } }
    manifest_hash = Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(manifest))
    text = Portal::ApprovalText.for(locale)
    views = Portal::DocumentView.where(portal_user_id: person.id, publication_file_id: files.map(&:id)).includes(:publication_file).map { |v| { "file" => v.publication_file.token, "viewed_at" => v.viewed_at.utc.iso8601(6) } }
    evidence = {
      "version" => 1,
      "publication" => { "token" => publication.token, "version" => publication.version, "title" => publication.title, "kind" => publication.kind, "company_id" => publication.entity_id,
                         "published_at" => publication.published_at.utc.iso8601(6) },
      "manifest" => manifest, "manifest_hash" => manifest_hash, "decision" => decision, "comment" => comment,
      "approver" => { "id" => person.id, "email" => person.email, "full_name" => person.full_name, "identity_verified_at" => person.identity_verified_at&.utc&.iso8601(6) },
      "decided_at" => Time.current.utc.iso8601(6), "ip" => ip, "user_agent_sha256" => Digest::SHA256.hexdigest(user_agent.to_s),
      "second_factor" => { "method" => session.second_factor_method, "at" => session.second_factor_at&.utc&.iso8601(6) },
      "viewed" => views.sort_by { |v| v["file"] },
      "legal_text" => { "version" => Portal::ApprovalText::VERSION, "locale" => locale.to_s, "sha256" => Digest::SHA256.hexdigest(text), "text" => text }
    }
    create!(publication: publication, portal_user: person, entity_id: publication.entity_id, decision: decision, comment: comment, manifest_hash: manifest_hash, evidence: evidence,
            evidence_hash: Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(evidence)))
  end
end
