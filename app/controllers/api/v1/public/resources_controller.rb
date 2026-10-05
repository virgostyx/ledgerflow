# F13c: the read-only collections of the public API, from Api::V1::Resources: one controller, one route per resource, the scope of the resource.
class Api::V1::Public::ResourcesController < Api::V1::Public::BaseController
  # the scope depends on the resource asked: any token gets in, and `require_resource_scope` asks for the scope of that resource
  self.action_scopes = { index: :any, show: :any }
  before_action :require_resource_scope

  def index
    resource = current_resource
    page = paginate(resource.relation.call, sorts: resource.sorts, filters: resource.filters)
    return if performed?

    render json: { data: page[:rows].map { |row| Api::V1::Resources.serialize(resource, row) }, meta: page[:meta] }
  end

  def show
    resource = current_resource
    record = resource.relation.call.find(params[:id])
    etag = etag_for(resource.name, record.id, record.updated_at&.iso8601(6))
    response.set_header("ETag", etag)
    return head(:not_modified) if request.headers["If-None-Match"] == etag

    render json: { data: Api::V1::Resources.serialize(resource, record) }
  end

  private

  def current_resource = Api::V1::Resources::REGISTRY.fetch(params[:resource])

  def require_resource_scope
    scope = current_resource.scope
    deny(:forbidden, "Forbidden", required_scope: scope) unless @api_client.allows?(scope)
  end
end
