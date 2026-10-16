# B02b: who may send to the documents address of a company, and whether the receiving server vouched for them. A sender is allowed if they are a person of the company's portal who may send
# documents, or an address the firm listed. The server vouched if the Authentication-Results written by OUR server (its name is configured) says SPF and DKIM passed; a header a sender wrote
# himself, or none, proves nothing.
# => nil when the mail is to be taken in, else the reason it goes to quarantine
class PortalAdmin::ScreenMail
  def self.call(entity:, mail:)
    sender = mail.from&.first.to_s.strip.downcase
    return "sender_not_allowed" unless allowed?(entity, sender)

    "authentication_failed" unless vouched?(mail)
  end

  def self.allowed?(entity, sender)
    return false if sender.blank?
    return true if entity.documents_allowed_senders.map(&:downcase).include?(sender)

    granted = Portal::Grant.in_force.where(entity_id: entity.id).where("capabilities @> ?", [ "documents.upload" ].to_json).select(:portal_user_id)
    PortalUser.active.where(id: granted).where("lower(email) = ?", sender).exists?
  end

  def self.vouched?(mail)
    server = Rails.configuration.x.mail_authserv_id.to_s.downcase
    return false if server.blank?

    mail.header.fields.select { |field| field.name.casecmp?("Authentication-Results") }.map { |field| field.value.to_s.downcase }.any? do |value|
      value.start_with?("#{server};", "#{server} ") && value.match?(/\bspf=pass\b/) && value.match?(/\bdkim=pass\b/)
    end
  end

  # A machine's message (a bounce, a list, an automatic reply) is not answered: two machines would answer each other for ever.
  def self.automatic?(mail)
    auto = mail.header["Auto-Submitted"]&.value.to_s.strip.downcase
    bounce = mail.header["Return-Path"].present? && mail.return_path.blank? # a null return path: the message of a machine
    (auto.present? && auto != "no") || mail.header["Precedence"]&.value.to_s.strip.downcase.in?(%w[bulk list junk auto_reply]) || bounce
  end
  private_class_method :allowed?, :vouched?
end
