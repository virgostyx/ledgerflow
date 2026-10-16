# B02b: one chunk of an upload, as raw bytes with its SHA-256 in X-Chunk-SHA256.
class Portal::UploadChunksController < Portal::BaseController
  def update
    upload = Portal::Upload.of(current_portal_user).find_by(token: params[:token])
    return not_in_scope(params[:token]) unless upload
    return head(:content_too_large) if request.content_length.to_i > Portal::Upload::CHUNK_SIZE

    upload.store_chunk!(params[:position].to_i, request.raw_post.b, request.headers["X-Chunk-SHA256"])
    render json: { received: upload.received_positions }
  rescue Portal::UploadRefused => e
    render json: { error: e.message }.merge(e.detail), status: e.status
  end
end
