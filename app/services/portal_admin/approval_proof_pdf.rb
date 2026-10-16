# B02c: the document "Proof of approval" the firm downloads: who decided what, on which files (name, size, fingerprint), when, from where, how the second factor was given, the text shown, the
# fingerprint of the proof and its seal, and how to verify it without the application.
class PortalAdmin::ApprovalProofPdf
  def self.call(approval)
    ev = approval.evidence
    Prawn::Document.new(page_size: "A4", margin: 40) do |pdf|
      pdf.text "Proof of approval", size: 20, style: :bold
      pdf.move_down 6
      pdf.text "#{ev['publication']['title']} - version #{ev['publication']['version']}", size: 12
      pdf.move_down 10
      rows = [
        [ "Decision", approval.decision.tr("_", " ") ], [ "Remarks", approval.comment.to_s ],
        [ "Decided by", "#{ev['approver']['full_name']} (#{ev['approver']['email']})" ], [ "Identity verified by the firm", ev["approver"]["identity_verified_at"].to_s ],
        [ "Decided at (UTC)", ev["decided_at"] ], [ "From address", ev["ip"].to_s ], [ "Browser (SHA-256)", ev["user_agent_sha256"] ],
        [ "Second factor", "#{ev['second_factor']['method']} at #{ev['second_factor']['at']}" ], [ "Status", approval.status ]
      ]
      pdf.table(rows, width: pdf.bounds.width, cell_style: { size: 9, inline_format: false }) { column(0).font_style = :bold; column(0).width = 150 }
      pdf.move_down 12
      pdf.text "Files approved", style: :bold
      pdf.table([ %w[File Bytes SHA-256] ] + ev["manifest"].map { |m| [ m["filename"], m["byte_size"].to_s, m["sha256"] ] }, width: pdf.bounds.width, cell_style: { size: 7 }) { row(0).font_style = :bold }
      pdf.move_down 6
      pdf.text "Fingerprint of the manifest: #{approval.manifest_hash}", size: 8
      pdf.move_down 12
      pdf.text "Text shown to the person (version #{ev['legal_text']['version']}, #{ev['legal_text']['locale']})", style: :bold
      pdf.text ev["legal_text"]["text"], size: 9
      pdf.move_down 12
      pdf.text "Seal", style: :bold
      pdf.text "Fingerprint of the proof (SHA-256 of the canonical JSON, RFC 8785): #{approval.evidence_hash}", size: 8
      pdf.text(approval.sealed? ? "Signed with key #{approval.seal_key_id} (Ed25519) on #{approval.sealed_at.utc.iso8601}. Signature: #{approval.seal_signature}" : "Not sealed yet.", size: 8)
      pdf.move_down 8
      pdf.text "To verify: take the evidence, write it in canonical JSON (RFC 8785), hash it with SHA-256 and compare it with the fingerprint above; then verify the signature of " \
               "{\"type\":\"client_approval\",\"evidence_hash\":...,\"evidence\":...} with the public key published at /.well-known/ledgerflow/keys.json.", size: 8
    end.render
  end
end
