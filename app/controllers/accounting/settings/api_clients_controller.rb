# Third-party applications that push data through the API (docs/dev/api/inbound-api.md).
# The plaintext key is rendered once, in the response to create/rotate, and never stored.
class Accounting::Settings::ApiClientsController < Accounting::Settings::BaseController
  before_action :require_api!
  before_action :set_client, only: [ :rotate, :revoke ]

  def index
    @clients = clients.includes(:owner).order(:name)
  end

  def new
    @client = ApiClient.new(scopes: [])
  end

  def create
    @client, @key = ApiClient.issue!(**client_params.to_h.symbolize_keys, entity: current_entity, owner: current_user)
    render :key
  rescue ActiveRecord::RecordInvalid => e
    @client = e.record
    render :new, status: :unprocessable_content
  end

  def rotate
    @client.update!(owner: current_user) if @client.owner.nil? # re-issuing the key is when it gets an owner
    @key = @client.rotate!
    render :key
  end

  def revoke
    @client.revoke!
    redirect_to accounting_settings_api_clients_path, notice: "API client revoked."
  end

  private

  def authorize_settings_access!
    return if Accounting::Settings::BasePolicy.new(current_user, :settings).destroy?

    flash[:alert] = t("errors.not_authorized")
    redirect_to accounting_root_path
  end

  def current_entity = ActsAsTenant.current_tenant

  # The screen does not exist for an entity that neither declared the BudgetFlow integration nor turned the public API on (F13).
  def require_api!
    head :not_found unless budgetflow_enabled? || feature?(:f13)
  end

  def clients = ApiClient.where(entity: current_entity)

  def set_client
    @client = clients.find(params[:id])
  end

  def client_params
    params.require(:api_client).permit(:name, :expires_at, :rate_limit_per_minute, scopes: []).tap do |p|
      p[:scopes] = Array(p[:scopes]).compact_blank
      p[:expires_at] = p[:expires_at].presence&.then { |date| Date.iso8601(date).end_of_day } rescue nil
      p.delete(:rate_limit_per_minute) if p[:rate_limit_per_minute].blank?
    end
  end
end
