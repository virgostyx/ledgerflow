# B02b: tells a client that something they sent needs their attention (to complete, or refused). The mail says that and where to look, never what: no name of a file, no amount.
# A mail that cannot be sent never fails what the firm just did.
class PortalAdmin::NotifyUpload
  def self.call(upload)
    return if upload.portal_user.notification_frequency == "off"

    Portal::NotificationMailer.upload_needs_attention(upload.portal_user, Portal::Company.find(upload.entity_id).name).deliver_now
  rescue StandardError => e
    Rails.logger.error("portal notification not sent: #{e.class}")
  end
end
