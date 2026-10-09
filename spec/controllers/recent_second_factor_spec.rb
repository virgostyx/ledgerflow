require "rails_helper"

# Signature functions (§2.2, B01a/B01b): a sensitive action asks for a *recent* second factor, not only the one given at sign-in.
RSpec.describe ApplicationController, type: :controller do
  include_context "with entity"

  controller do
    skip_before_action :set_current_entity, :require_entity!, raise: false
    before_action { require_recent_second_factor!(within: 5.minutes) }

    def index = head(:ok)
  end

  let(:user) { create(:user, role: :admin) }

  around do |example|
    previous = Rails.configuration.x.second_factor_required
    Rails.configuration.x.second_factor_required = true
    example.run
  ensure
    Rails.configuration.x.second_factor_required = previous
  end

  before do
    sign_in user
    allow(user).to receive(:totp_enabled?).and_return(true)
    allow(controller).to receive(:current_user).and_return(user)
  end

  it "stamps the moment the second factor is given" do
    freeze_time do
      controller.send(:second_factor_passed!, user)

      expect(session[:second_factor_user_id]).to eq(user.id)
      expect(session[:second_factor_at]).to eq(Time.current.to_i)
    end
  end

  it "lets a second factor given a minute ago through" do
    controller.send(:second_factor_passed!, user)
    travel 1.minute

    get :index

    expect(response).to have_http_status(:ok)
  end

  it "asks again once the second factor is older than the window, and remembers where to come back" do
    controller.send(:second_factor_passed!, user)
    travel 6.minutes

    get :index

    expect(response).to redirect_to(two_factor_challenge_path)
    expect(session[:after_second_factor_path]).to eq("/anonymous")
  end

  it "asks for a second factor when none was given in this session" do
    get :index

    expect(response).to redirect_to(two_factor_challenge_path)
  end

  it "does not accept a second factor given by someone else in the same session" do
    controller.send(:second_factor_passed!, create(:user))

    get :index

    expect(response).to redirect_to(two_factor_challenge_path)
  end

  it "sends someone with no second factor to enrol" do
    allow(user).to receive(:totp_enabled?).and_return(false)

    get :index

    expect(response).to redirect_to(two_factor_path)
  end

  it "stays out of the way where second factors are switched off (development, test)" do
    Rails.configuration.x.second_factor_required = false

    get :index

    expect(response).to have_http_status(:ok)
  end
end
