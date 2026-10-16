class Portal::SessionsController < Portal::BaseController
  skip_before_action :require_sign_in!

  # Compared when the address is unknown, so that an unknown address takes as long as a known one.
  DUMMY_DIGEST = BCrypt::Password.create("not a password", cost: BCrypt::Engine.cost)

  def new; end

  def create
    user = PortalUser.find_by_email(params[:email])
    if user && !user.locked? && user.authenticate(params[:password].to_s) && (user.active? || user.invited?)
      user.register_success!
      start_session!(user)
      Portal::Event.record!("sign_in", user: user, request: request)
      redirect_to(user.second_factor_configured? ? portal_second_factor_challenge_path : new_portal_second_factor_path)
    else
      BCrypt::Password.new(DUMMY_DIGEST) == params[:password].to_s unless user
      user&.register_failure! unless user&.locked?
      Portal::Event.record!("sign_in_failed", user: user, email_tried: params[:email], request: request)
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    record_event("sign_out") if current_portal_user
    # What the browser keeps for the portal (copies of pages, and, if the person asked, the documents waiting to be sent) goes with the session.
    response.set_header("Clear-Site-Data", current_portal_user&.wipe_outbox_on_sign_out? ? '"cache", "storage"' : '"cache"')
    end_session!
    redirect_to portal_sign_in_path
  end
end
