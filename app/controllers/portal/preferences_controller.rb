class Portal::PreferencesController < Portal::BaseController
  def show; end

  def update
    changes = { wipe_outbox_on_sign_out: params[:wipe_outbox_on_sign_out] == "1" }
    changes[:notification_frequency] = params[:notification_frequency].to_s if params.key?(:notification_frequency)
    if current_portal_user.update(changes)
      redirect_to preferences_path, notice: "Saved."
    else
      flash.now[:alert] = "Choose immediately, once a day or never."
      render :show, status: :unprocessable_content
    end
  end
end
