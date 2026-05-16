class Api::V1::BaseController < ActionController::API
  before_action :authenticate_api_request!

  private

  def authenticate_api_request!
    token = request.headers["Authorization"]&.split(" ")&.last
    @api_payload = Api::JwtService.decode(token)
  rescue Api::AuthenticationError
    render json: { error: "Unauthorized" }, status: :unauthorized
  end
end
