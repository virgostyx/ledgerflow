# A file of a publication, through a link signed for five minutes. The scope is read again here: a right revoked since the link was given stops the download.
class Portal::DownloadsController < Portal::BaseController
  def show
    file_token = Portal::DownloadLink.resolve(params[:signed], current_portal_user)
    file = file_token && Portal::PublicationFile.find_by(token: file_token)
    publication = file && Portal::Publication.in_reach_of(current_portal_user).visible.find_by(id: file.publication_id)
    return not_in_scope(file_token || params[:signed].to_s.first(12)) unless publication

    unless file.intact?
      record_event("download_integrity_failed", entity_id: publication.entity_id, target_token: file.token)
      return head(:internal_server_error)
    end

    data = publication.watermark && Accounting::WatermarkFile.markable?(file.content_type) ? Accounting::WatermarkFile.call(file.content, file.content_type, current_portal_user.full_name) : file.content
    record_event("publication_downloaded", entity_id: publication.entity_id, target_token: file.token)
    send_data data, filename: file.filename, type: file.content_type, disposition: "attachment"
  rescue Accounting::WatermarkFile::Unavailable
    head :service_unavailable # never an unmarked file when it should be marked
  end
end
