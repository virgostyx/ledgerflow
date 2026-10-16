class Portal::InvitationsController < Portal::BaseController
  skip_before_action :require_sign_in!
  before_action :find_invitation

  def show; end

  def accept
    user = @invitation.portal_user
    if user.update(password: params[:password].to_s, password_confirmation: params[:password_confirmation].to_s)
      @invitation.accept!
      start_session!(user)
      Portal::Event.record!("invitation_accepted", user: user, entity_id: @invitation.entity_id, request: request)
      redirect_to new_portal_second_factor_path
    else
      flash.now[:alert] = user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  private

  # An invitation that is unknown, used or out of date looks the same: nothing is told of why.
  def find_invitation
    @invitation = Portal::Invitation.find_usable(params[:token])
    head :not_found unless @invitation
  end
end
