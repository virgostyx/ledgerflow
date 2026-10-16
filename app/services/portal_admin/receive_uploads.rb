# B02b: the round that takes quarantine out, every minute (PortalAdminJob). A batch of photos waits until all its pages have come; a company that turned the feature off waits too.
class PortalAdmin::ReceiveUploads
  def self.call
    ready = Portal::Upload.received.where(entity_id: Portal::Company.where(upload_enabled: true).select(:id)).order(:received_at, :id).to_a
    singles, pages = ready.partition { |upload| upload.batch_token.blank? }
    singles.each { |upload| PortalAdmin::ReceiveUpload.call(upload) }
    pages.group_by { |upload| [ upload.portal_user_id, upload.batch_token ] }.each_value do |batch|
      next unless batch.size >= batch.first.page_count.to_i

      PortalAdmin::ReceiveUpload.call(batch.sort_by(&:page_number))
    end
  end
end
