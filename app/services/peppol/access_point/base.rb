# The contract of an Access Point adapter (see the shared examples "a Peppol access point"):
# - send_document: hands a UBL document to the AP and returns the message id it gives; raises Error if refused;
# - registered?: whether a participant is on the network; true, false or nil when unknown or not supported;
# - parse_webhook: checks the signature of a call from the AP and turns it into Peppol::Event objects;
# - .credential_fields: the credentials an entity must give, [{ key:, label:, required:, secret: }].
class Peppol::AccessPoint::Base
  attr_reader :entity

  def self.credential_fields = []

  def initialize(entity)
    @entity = entity
  end

  def send_document(xml:, sender:, receiver:, document_id:) = raise(NotImplementedError)

  def registered?(_participant_id) = nil

  def parse_webhook(headers:, body:) = raise(NotImplementedError)

  private

  def credential(key) = entity.peppol_credentials.to_h[key].presence

  def signature_valid?(body, signature, secret)
    return false if secret.blank? || signature.blank?

    ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA256", secret, body), signature.to_s)
  end

  def parsed_json(body)
    JSON.parse(body)
  rescue JSON::ParserError
    raise Peppol::AccessPoint::Error, "The webhook body is not valid JSON"
  end
end
