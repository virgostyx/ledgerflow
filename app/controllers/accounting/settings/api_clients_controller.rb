# Third-party applications that push data through the API (docs/dev/api/inbound-api.md).
# The plaintext key is rendered once, in the response to create/rotate, and never stored.
class Accounting::Settings::ApiClientsController < Accounting::Settings::BaseController
  before_action :set_client, only: [ :rotate, :revoke ]

  def index
    @clients = clients.order(:name)
  end

  def new
    @client = ApiClient.new(scopes: [])
  end

  def create
    @client, @key = ApiClient.issue!(**client_params.to_h.symbolize_keys, entity: current_entity)
    render :key
  rescue ActiveRecord::RecordInvalid => e
    @client = e.record
    render :new, status: :unprocessable_content
  end

  def rotate
    @key = @client.rotate!
    render :key
  end

  def revoke
    @client.revoke!
    redirect_to accounting_settings_api_clients_path, notice: "API client revoked."
  end

  private

  def authorize_settings_access!
    return if current_user.admin?

    flash[:alert] = t("errors.not_authorized")
    redirect_to accounting_root_path
  end

  def current_entity = ActsAsTenant.current_tenant

  def clients = ApiClient.where(entity: current_entity)

  def set_client
    @client = clients.find(params[:id])
  end

  def client_params
    params.require(:api_client).permit(:name, scopes: []).tap { |p| p[:scopes] = Array(p[:scopes]).compact_blank }
  end
end
