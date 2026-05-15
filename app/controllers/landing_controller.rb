class LandingController < ApplicationController
  layout "landing"
  skip_before_action :authenticate_user!, raise: false

  def index
    redirect_to accounting_root_path if user_signed_in?
  end
end
