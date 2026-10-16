# B02b: sending a file in chunks (JSON, resumable). The session belongs to the person who opened it; anyone else, and anyone whose right is gone, gets a 404.
class Portal::UploadsController < Portal::BaseController
  def create
    company = Portal::Upload.companies_open_to(current_portal_user).find_by(id: params[:company])
    return not_in_scope(params[:company]) unless company

    size = params[:byte_size].to_i
    upload = Portal::Upload.new(entity_id: company.id, portal_user: current_portal_user, filename: File.basename(params[:filename].to_s.tr("\\", "/")).first(255), content_type: params[:content_type].to_s.first(100),
                                byte_size: size, sha256: params[:sha256].to_s, chunk_size: Portal::Upload::CHUNK_SIZE, chunk_count: [ (size.to_f / Portal::Upload::CHUNK_SIZE).ceil, 1 ].max,
                                expires_at: Portal::Upload::VALIDITY.from_now, hint_kind: params[:hint_kind].presence || "purchase", hint_note: params[:hint_note].to_s.strip.presence)
    return render(json: { errors: upload.errors.full_messages }, status: :unprocessable_content) unless upload.save

    record_event("upload_started", entity_id: company.id, target_token: upload.token, filename: upload.filename, byte_size: upload.byte_size)
    render json: state(upload), status: :created
  end

  def show
    upload = mine or return
    render json: state(upload)
  end

  def complete
    upload = mine or return
    upload.complete!
    record_event("upload_received", entity_id: upload.entity_id, target_token: upload.token, filename: upload.filename, byte_size: upload.byte_size, sha256: upload.sha256)
    render json: state(upload).merge(receipt(upload))
  rescue Portal::UploadRefused => e
    render json: { error: e.message }.merge(e.detail), status: e.status
  end

  private

  def mine
    upload = Portal::Upload.of(current_portal_user).find_by(token: params[:token])
    not_in_scope(params[:token]) unless upload
    upload
  end

  def state(upload)
    { token: upload.token, status: upload.status, chunk_size: upload.chunk_size, chunk_count: upload.chunk_count, received: upload.received_positions, expires_at: upload.expires_at.iso8601 }
  end

  # What the person keeps: identifier, the server's time, the name and the start of the fingerprint.
  def receipt(upload)
    { filename: upload.filename, received_at: upload.received_at.iso8601, sha256_start: upload.sha256.first(12) }
  end
end
