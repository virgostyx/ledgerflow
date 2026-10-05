# F13c: the documentation of the public API: the OpenAPI document itself (JSON) and a page that reads it. Public: it describes, it does not give access.
class Api::DocsController < ActionController::Base
  def show
    @document = Api::V1::OpenApi.document
    render :show, layout: false
  end

  def openapi
    expires_in 5.minutes, public: true
    render json: Api::V1::OpenApi.document
  end
end
