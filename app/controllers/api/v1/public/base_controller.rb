# The public API (F13c). On top of the authentication of Api::V1::BaseController (a personal token: owner, scopes within the owner's rights, expiry):
# errors as problem+json (RFC 9457), a rate of its own per token with explicit headers, cursor pagination with filters and sorts, ETag and
# If-Match on updates, and replay of a POST by its Idempotency-Key. Everything goes through the services and policies of the application.
class Api::V1::Public::BaseController < Api::V1::BaseController
  PROBLEM_TYPE = "https://ledgerflow.app/problems/".freeze
  DEFAULT_PAGE = 50
  MAX_PAGE = 200

  self.surface = :public

  before_action :throttle!
  before_action :act_as_the_owner
  after_action :audit_write
  rescue_from ActiveRecord::RecordNotFound do |_e|
    problem(:not_found, "Not found", detail: "No such resource in this entity.", slug: "not-found")
  end
  rescue_from ActionController::ParameterMissing do |e|
    problem(:bad_request, "Missing parameter", detail: e.message, slug: "missing-parameter")
  end

  private

  # --- errors -------------------------------------------------------------------------------------------------------

  def problem(status, title, detail: nil, slug: nil, **extra)
    code = Rack::Utils::SYMBOL_TO_STATUS_CODE.fetch(status.to_sym) { status.to_i }
    body = { type: "#{PROBLEM_TYPE}#{slug || title.parameterize}", title: title, status: code, detail: detail, instance: request.path, request_id: request.request_id }
    render json: body.merge(extra).compact, status: code, content_type: "application/problem+json"
  end

  def deny(status, error, required_scope: nil, **)
    detail = required_scope ? "This token lacks the scope #{required_scope}." : nil
    headers = status == :unauthorized ? { "WWW-Authenticate" => 'Bearer realm="ledgerflow"' } : {}
    headers.each { |k, v| response.set_header(k, v) }
    problem(status, error, detail: detail, slug: error.parameterize, required_scope: required_scope)
  end

  def unprocessable(message, errors: nil) = problem(:unprocessable_content, "Unprocessable", detail: message, slug: "unprocessable", errors: errors)

  # --- who -----------------------------------------------------------------------------------------------------------

  # The services read the person (Current.user): the owner of the token, who is the one answering for what it does.
  def act_as_the_owner
    Current.user = @api_client.owner
    @owner_membership = @api_client.owner_membership
  end

  # --- rate ----------------------------------------------------------------------------------------------------------

  # A window of a minute per token, counted by Rack::Attack's own store. The limit is the token's.
  def throttle!
    limit  = @api_client.rate_limit_per_minute
    period = 60
    count  = Rack::Attack.cache.count("api/token/#{@api_client.id}", period)
    reset  = period - (Time.now.to_i % period)
    response.set_header("RateLimit-Limit", limit.to_s)
    response.set_header("RateLimit-Remaining", [ limit - count, 0 ].max.to_s)
    response.set_header("RateLimit-Reset", reset.to_s)
    return unless count > limit

    response.set_header("Retry-After", reset.to_s)
    problem(:too_many_requests, "Too many requests", detail: "The limit of this token is #{limit} requests a minute.", slug: "rate-limited", retry_after: reset)
  end

  # --- list: filters, sorts, cursor ---------------------------------------------------------------------------------

  # `sorts`: { "name" => "sql column" } (a column that is never null); `filters`: { "param" => ->(scope, value) { scope } }. The cursor is
  # opaque: the last sort value and id. Output: { data:, meta: { next_cursor:, has_more: } }.
  def paginate(scope, sorts:, filters: {}, default_sort: "id")
    filters.each do |name, apply|
      value = params.dig(:filter, name)
      scope = apply.call(scope, value) if value.present?
    end
    unknown = (params[:filter]&.keys.to_a - filters.keys)
    return problem(:bad_request, "Unknown filter", detail: "Known filters: #{filters.keys.join(', ')}.", slug: "unknown-filter") if unknown.any?

    sort = params[:sort].presence || default_sort
    descending = sort.start_with?("-")
    column = sorts[sort.delete_prefix("-")] or return problem(:bad_request, "Unknown sort", detail: "Known sorts: #{sorts.keys.join(', ')}.", slug: "unknown-sort")
    size = (params.dig(:page, :size) || DEFAULT_PAGE).to_i.clamp(1, MAX_PAGE)
    scope = after_cursor(scope, sorts.fetch("id"), column, descending, params.dig(:page, :after))
    return if performed?

    rows = scope.reorder(Arel.sql("#{column} #{descending ? 'DESC' : 'ASC'}, #{sorts.fetch('id')} ASC")).limit(size + 1).to_a
    more = rows.size > size
    rows = rows.first(size)
    { rows: rows, meta: { has_more: more, next_cursor: (more ? cursor_for(rows.last, sorts, column) : nil) } }
  end

  def after_cursor(scope, id_column, column, descending, cursor)
    return scope if cursor.blank?

    value, id = JSON.parse(Base64.urlsafe_decode64(cursor)).values_at("v", "id")
    key = "#{column} #{descending ? '<' : '>'} :v OR (#{column} = :v AND #{id_column} > :id)"
    scope.where(key, v: value, id: id)
  rescue ArgumentError, JSON::ParserError
    problem(:bad_request, "Invalid cursor", detail: "The cursor is not one this API gave.", slug: "invalid-cursor")
    scope
  end

  def cursor_for(row, sorts, column)
    value, id = row.class.unscoped.where(id: row.id).pick(Arel.sql(column), Arel.sql(sorts.fetch("id")))
    Base64.urlsafe_encode64(JSON.generate(v: value.respond_to?(:iso8601) ? value.iso8601(6) : value, id: id), padding: false)
  end

  # --- ETag and If-Match ---------------------------------------------------------------------------------------------

  def etag_for(*parts) = %("#{Digest::SHA256.hexdigest(parts.flatten.join('|'))[0, 32]}")

  # 428 when the caller sent no precondition, 412 when it is stale: no blind overwrite.
  def require_current!(etag)
    given = request.headers["If-Match"]
    return true if given.present? && (given.split(",").map(&:strip).include?(etag) || given.strip == "*")

    if given.blank?
      problem(:precondition_required, "Precondition required", detail: "Send the ETag you read in If-Match.", slug: "precondition-required")
    else
      problem(:precondition_failed, "Precondition failed", detail: "The resource changed since you read it: read it again.", slug: "precondition-failed")
    end
    false
  end

  # --- Idempotency-Key -----------------------------------------------------------------------------------------------

  # Wrap a POST that creates or changes data. The same key with the same request gives the stored answer; with another request, an error.
  def idempotently
    key = request.headers["Idempotency-Key"].presence
    return yield unless key

    fingerprint = Digest::SHA256.hexdigest([ request.method, request.path, request.raw_post ].join("\n"))
    record = ApiIdempotencyKey.create_or_find_by!(api_client: @api_client, key: key.first(255)) { |r| r.request_fingerprint = fingerprint }
    return replay(record, fingerprint) unless record.previously_new_record?

    yield
    # a server error or a rate limit is not an answer to keep: the caller may try again with the same key
    return record.destroy if response.status >= 500 || response.status == 429

    record.update!(response_status: response.status, response_body: parsed_body, response_headers: response.headers.slice("Location", "ETag", "Content-Type").to_h)
  rescue StandardError
    ApiIdempotencyKey.where(api_client: @api_client, key: key.to_s.first(255), response_status: nil).delete_all
    raise
  end

  def replay(record, fingerprint)
    return problem(:unprocessable_content, "Idempotency key reused", detail: "This key was used for another request.", slug: "idempotency-key-reused") if record.request_fingerprint != fingerprint
    return problem(:conflict, "Request in progress", detail: "The first request with this key is still running.", slug: "idempotency-in-progress") unless record.finished?

    record.response_headers.each { |name, value| response.set_header(name, value) }
    response.set_header("Idempotent-Replayed", "true")
    render json: record.response_body, status: record.response_status, content_type: record.response_headers["Content-Type"]
  end

  def parsed_body = response.body.present? ? JSON.parse(response.body) : nil

  # --- audit of what is written ---------------------------------------------------------------------------------------

  def audit_write
    return if request.get? || request.head?

    Accounting::AuditLog.record!(auditable: ActsAsTenant.current_tenant, action: "api_write", user: @api_client.owner,
                                 payload: { http_method: request.method, path: request.path, status: response.status, token: @api_client.name, token_id: @api_client.id,
                                            idempotency_key: request.headers["Idempotency-Key"].present? })
  end
end
