# F13c: a personal token of the public API, and the calls made with it.
module ApiHelpers
  def owner_with(role, entity: self.entity) = create(:user).tap { |user| create(:user_entity, role, user: user, entity: entity) }

  def token_for(scopes, role: :accountant, entity: self.entity, **attrs)
    ApiClient.issue!(entity: entity, name: "Test token", scopes: scopes, owner: owner_with(role, entity: entity), **attrs).last
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  def api_get(path, token, params: {}, headers: {}) = get(path, params: params, headers: auth(token).merge(headers))

  def api_post(path, token, body = {}, headers: {}) = post(path, params: body.to_json, headers: auth(token).merge("Content-Type" => "application/json").merge(headers))

  def api_patch(path, token, body = {}, headers: {}) = patch(path, params: body.to_json, headers: auth(token).merge("Content-Type" => "application/json").merge(headers))

  def json = JSON.parse(response.body)
end

RSpec.configure { |config| config.include ApiHelpers, type: :request }
