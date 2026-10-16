class Portal::PreferencesController < Portal::BaseController
  def show; end

  def update
    if current_portal_user.update(notification_frequency: params[:notification_frequency].to_s)
      redirect_to preferences_path, notice: "Saved."
    else
      flash.now[:alert] = "Choose immediately, once a day or never."
      render :show, status: :unprocessable_content
    end
  end
end
