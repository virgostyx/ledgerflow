class Portal::PublicationsController < Portal::BaseController
  def index
    @publications = Portal::Publication.in_reach_of(current_portal_user).visible.includes(:company, :files).order(published_at: :desc)
  end

  def show
    reachable = Portal::Publication.in_reach_of(current_portal_user)
    @publication = reachable.visible.includes(:files).find_by(token: params[:token])
    return render(:gone, status: :not_found) if @publication.nil? && reachable.exists?(token: params[:token], status: "withdrawn")
    return head(:not_found) unless @publication

    record_event("publication_viewed", entity_id: @publication.entity_id, target_token: @publication.token)
    @links = @publication.files.index_with { |file| Portal::DownloadLink.for(current_portal_user, file) }
  end
end
