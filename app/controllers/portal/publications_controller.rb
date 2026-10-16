class Portal::PublicationsController < Portal::BaseController
  def index
    @publications = Portal::Publication.in_reach_of(current_portal_user).visible.includes(:company, :files).order(published_at: :desc)
  end

  def show
    reachable = Portal::Publication.in_reach_of(current_portal_user)
    @publication = reachable.visible.includes(:files).find_by(token: params[:token])
    return render(:gone, status: :not_found) if @publication.nil? && reachable.exists?(token: params[:token], status: "withdrawn")
    return not_in_scope(params[:token]) unless @publication

    record_event("publication_viewed", entity_id: @publication.entity_id, target_token: @publication.token)
    prepare
  end

  # B02c: the decision of a person named to approve the accounts of a publication (see Portal::Approval).
  def approve
    publication = Portal::Publication.in_reach_of(current_portal_user).includes(:files).find_by(token: params[:token])
    return not_in_scope(params[:token]) unless publication&.approver?(current_portal_user) && current_portal_user.qualified_approver_in?(publication.entity_id)
    @publication = publication
    return refuse_approval(t("portal.approvals.gone"), :gone) unless publication.published? && publication.replaced_by_id.nil?

    decision = params[:decision].to_s
    comment = Portal::Answer.clean(params[:comment])
    problem = if Portal::Approval::DECISIONS.exclude?(decision) then t("portal.approvals.choose")
    elsif !all_opened? then t("portal.approvals.open_first")
    elsif params[:confirm] != "1" then t("portal.approvals.confirm_needed")
    elsif decision != "approved" && comment.blank? then t("portal.approvals.comment_needed")
    end
    return refuse_approval(problem, :unprocessable_content) if problem

    unless current_portal_session.second_factor_recent? # a new authentication for each decision
      return redirect_to(portal_second_factor_challenge_path(return_to: publication_path(publication)), alert: t("portal.approvals.authenticate"))
    end

    begin
      approval = Portal::Approval.record!(publication: publication, person: current_portal_user, session: current_portal_session, decision: decision, comment: comment.presence, ip: request.remote_ip,
                                          user_agent: request.user_agent, locale: I18n.locale)
    rescue ActiveRecord::RecordNotUnique
      return refuse_approval(t("portal.approvals.already"), :conflict)
    end
    record_event("publication_#{decision}", entity_id: publication.entity_id, target_token: publication.token, approval: approval.evidence_hash)
    redirect_to publication_path(publication), notice: t("portal.approvals.thanks")
  end

  private

  def all_opened?
    ids = @publication.files.map(&:id)
    Portal::DocumentView.where(portal_user_id: current_portal_user.id, publication_file_id: ids).count == ids.size
  end

  def refuse_approval(message, status)
    flash.now[:alert] = message
    prepare
    render :show, status: status
  end

  def prepare
    @links = @publication.files.index_with { |file| Portal::DownloadLink.for(current_portal_user, file) }
    @approver = @publication.approver?(current_portal_user) && current_portal_user.qualified_approver_in?(@publication.entity_id)
    @opened = Portal::DocumentView.where(portal_user_id: current_portal_user.id, publication_file_id: @publication.files.map(&:id)).count == @publication.files.size
    @own = @publication.approvals.active.find_by(portal_user_id: current_portal_user.id)
    @legal_text = Portal::ApprovalText.for(I18n.locale)
  end
end
