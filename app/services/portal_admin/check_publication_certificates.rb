# B02c: checks again, from time to time, the integrity certificates attached to the publications still shown (a JSON file of the type of B03c): valid, revoked since, not valid any more, or
# unknown (the company never issued it). The portal says what was found, with the date, and never runs the verification itself.
class PortalAdmin::CheckPublicationCertificates
  TYPE = "ledgerflow-integrity-certificate".freeze

  def self.call
    Portal::Publication.visible.includes(:files).find_each do |publication|
      publication.files.select { |file| file.content_type == "application/json" }.each do |file|
        uuid = certificate_id(file.content) or next
        state = state_of(publication.entity_id, uuid)
        Portal::CertificateCheck.find_or_initialize_by(publication_id: publication.id).update!(state: state, checked_at: Time.current)
      end
    end
  end

  def self.certificate_id(content)
    json = JSON.parse(content)
    json["id"] if json.is_a?(Hash) && json["type"] == TYPE
  rescue JSON::ParserError
    nil
  end

  def self.state_of(entity_id, uuid)
    certificate = ActsAsTenant.without_tenant { IntegrityCertificate.find_by(entity_id: entity_id, uuid: uuid) }
    return "unknown" unless certificate

    case Integrity::VerifyCertificate.call(certificate).state
    when :valid then "valid"
    when :revoked then "revoked"
    else "not_valid"
    end
  end
  private_class_method :certificate_id, :state_of
end
