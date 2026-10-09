# F13c: the OpenAPI 3.1 document of the public API (`/api/v1/openapi.json`, served at `/api/docs`). It is made from the resources of
# Api::V1::Resources and from the description of the other endpoints below, so that the document, the routes and the controllers are written once;
# the specs check the document against the routes and against real answers (contract tests), and that it breaks nothing of the version that is
# published (docs/api/openapi-v1.json, see Api::V1::OpenApi::Compatibility).
module Api::V1::OpenApi
  VERSION = "1.0.0"
  PROBLEM_STATUSES = { 400 => "Bad request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not found", 409 => "Conflict", 412 => "Precondition failed",
                       422 => "Unprocessable", 428 => "Precondition required", 429 => "Too many requests", 503 => "Service unavailable" }.freeze
  TYPES = { integer: { "type" => %w[integer null] }, string: { "type" => %w[string null] }, boolean: { "type" => %w[boolean null] }, decimal: { "type" => %w[string null], "pattern" => '^-?\d+(\.\d+)?$' },
            date: { "type" => %w[string null], "format" => "date" }, datetime: { "type" => %w[string null], "format" => "date-time" } }.freeze

  def self.document
    {
      "openapi" => "3.1.0",
      "info" => { "title" => "LedgerFlow API", "version" => VERSION, "description" => description },
      "servers" => [ { "url" => "/api/v1" } ],
      "security" => [ { "bearerAuth" => [] } ],
      "paths" => paths,
      "components" => components
    }
  end

  def self.description
    "Personal access tokens (Settings, API tokens): `Authorization: Bearer lf_…`. A token has an owner, scopes that never go beyond the rights of the owner, an expiry and a rate " \
      "(60 requests a minute unless set otherwise; `RateLimit-*` headers on every answer). Errors are `application/problem+json`. Lists are paged by cursor " \
      "(`page[size]`, `page[after]`), filtered by `filter[name]` and sorted by `sort`. An update needs the `ETag` of the resource in `If-Match`; a POST accepts an `Idempotency-Key`. " \
      "Entries are created as drafts, validated by an explicit call, and reversed, never changed once validated."
  end

  def self.paths
    paths = {}
    Api::V1::Resources::REGISTRY.each_value do |r|
      paths["/#{r.name}"] = { "get" => list_operation(r) }
      paths["/#{r.name}/{id}"] = { "get" => show_operation(r) }
    end
    paths["/entries"] = { "get" => entries_list, "post" => entry_write("createEntry", "Create a draft entry", "entries:write", 201) }
    paths["/entries/{id}"] = { "get" => show_operation_for("getEntry", "Get an entry with its lines", "entries:read", "Entry"),
                               "patch" => entry_write("updateEntry", "Change a draft entry (If-Match required)", "entries:write", 200, if_match: true) }
    paths["/entries/{id}/post"] = { "post" => action("postEntry", "Validate a draft entry", "entries:post", 200) }
    paths["/entries/{id}/reverse"] = { "post" => action("reverseEntry", "Reverse a validated entry", "entries:reverse", 201, body: { "reason" => { "type" => "string" }, "date" => { "type" => "string", "format" => "date" } }) }
    paths["/reports/{name}"] = { "get" => report_operation }
    paths.merge!(Api::V1::OpenApi::AgentEndpoints.paths)
    paths.merge!(Api::V1::OpenApi::ApprovalEndpoints.paths)
    paths
  end

  def self.components
    schemas = { "Problem" => problem_schema, "PageMeta" => { "type" => "object", "required" => %w[has_more next_cursor],
                                                              "properties" => { "has_more" => { "type" => "boolean" }, "next_cursor" => { "type" => %w[string null] } } },
                "EntryLine" => entry_line_schema, "Entry" => entry_schema, "EntryInput" => entry_input_schema, "Report" => report_schema }
    Api::V1::Resources::REGISTRY.each_value { |r| schemas[schema_name(r)] = resource_schema(r) }
    schemas.merge!(Api::V1::OpenApi::AgentEndpoints.schemas)
    schemas.merge!(Api::V1::OpenApi::ApprovalEndpoints.schemas)
    { "securitySchemes" => { "bearerAuth" => { "type" => "http", "scheme" => "bearer", "description" => "A personal access token (lf_…)." } },
      "parameters" => { "PageSize" => { "name" => "page[size]", "in" => "query", "schema" => { "type" => "integer", "minimum" => 1, "maximum" => Api::V1::Public::BaseController::MAX_PAGE } },
                        "PageAfter" => { "name" => "page[after]", "in" => "query", "schema" => { "type" => "string" }, "description" => "The `next_cursor` of the previous page." },
                        "Id" => { "name" => "id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } },
                        "IfMatch" => { "name" => "If-Match", "in" => "header", "required" => true, "schema" => { "type" => "string" }, "description" => "The ETag read with the resource." },
                        "IdempotencyKey" => { "name" => "Idempotency-Key", "in" => "header", "required" => false, "schema" => { "type" => "string", "maxLength" => 255 } } }
                          .merge(Api::V1::OpenApi::AgentEndpoints.parameters),
      "responses" => PROBLEM_STATUSES.to_h { |code, title| [ "Problem#{code}", { "description" => title, "content" => { "application/problem+json" => { "schema" => { "$ref" => "#/components/schemas/Problem" } } } } ] },
      "schemas" => schemas }
  end

  def self.schema_name(resource) = resource.name.singularize.camelize

  def self.resource_schema(resource)
    { "type" => "object", "required" => resource.fields.keys,
      "properties" => resource.fields.to_h { |field, type| [ field, field == "id" ? { "type" => "integer" } : TYPES.fetch(type) ] } }
  end

  def self.problem_schema
    { "type" => "object", "required" => %w[type title status], "properties" => {
      "type" => { "type" => "string" }, "title" => { "type" => "string" }, "status" => { "type" => "integer" }, "detail" => { "type" => "string" },
      "instance" => { "type" => "string" }, "request_id" => { "type" => "string" }, "required_scope" => { "type" => "string" }, "retry_after" => { "type" => "integer" },
      "reason" => { "type" => "string" }, "findings" => { "type" => "array", "items" => { "type" => "object" } } } }
  end

  def self.entry_line_schema
    { "type" => "object", "required" => %w[id account debit credit], "properties" => {
      "id" => { "type" => "integer" }, "account" => { "type" => "string" }, "partner_id" => { "type" => %w[integer null] }, "label" => { "type" => %w[string null] },
      "debit" => TYPES[:decimal], "credit" => TYPES[:decimal] } }
  end

  def self.entry_schema
    { "type" => "object", "required" => %w[id status entry_date journal fiscal_year lines], "properties" => {
      "id" => { "type" => "integer" }, "reference" => { "type" => %w[string null] }, "status" => { "type" => "string", "enum" => %w[draft posted reversed] },
      "entry_date" => { "type" => "string", "format" => "date" }, "journal" => { "type" => "string" }, "fiscal_year" => { "type" => "integer" },
      "description" => { "type" => %w[string null] }, "external_id" => { "type" => %w[string null] }, "created_at" => { "type" => "string", "format" => "date-time" },
      "updated_at" => { "type" => "string", "format" => "date-time" }, "lines" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/EntryLine" } } } }
  end

  def self.entry_input_schema
    line = { "type" => "object", "required" => %w[account], "properties" => { "account" => { "type" => "string" }, "debit" => { "type" => "string" }, "credit" => { "type" => "string" },
                                                                           "label" => { "type" => "string" }, "partner_id" => { "type" => "integer" } } }
    { "type" => "object", "required" => %w[entry], "properties" => { "entry" => { "type" => "object", "required" => [], "properties" => {
      "journal" => { "type" => "string" }, "entry_date" => { "type" => "string", "format" => "date" }, "description" => { "type" => "string" }, "external_id" => { "type" => "string" },
      "lines" => { "type" => "array", "items" => line } } } } }
  end

  def self.report_schema
    { "type" => "object", "required" => %w[report currency generated_at rows totals], "properties" => {
      "report" => { "type" => "string" }, "currency" => { "type" => "string" }, "generated_at" => { "type" => "string", "format" => "date-time" }, "filters" => { "type" => %w[object null] },
      "warnings" => { "type" => "array" }, "totals" => { "type" => "object" }, "rows" => { "type" => "array", "items" => { "type" => "object" } } } }
  end

  # --- operations ---------------------------------------------------------------------------------------------------

  def self.problems(*codes) = codes.to_h { |code| [ code.to_s, { "$ref" => "#/components/responses/Problem#{code}" } ] }

  def self.ref(parameter) = { "$ref" => "#/components/parameters/#{parameter}" }

  def self.list_operation(resource)
    filters = resource.filters.keys.map { |name| { "name" => "filter[#{name}]", "in" => "query", "schema" => { "type" => "string" } } }
    sorts = resource.sorts.keys.flat_map { |name| [ name, "-#{name}" ] }
    { "operationId" => "list#{resource.name.camelize}", "summary" => "List: #{resource.description}", "x-required-scope" => resource.scope,
      "parameters" => [ ref("PageSize"), ref("PageAfter"), { "name" => "sort", "in" => "query", "schema" => { "type" => "string", "enum" => sorts } } ] + filters,
      "responses" => { "200" => { "description" => "A page", "content" => { "application/json" => { "schema" => { "type" => "object", "required" => %w[data meta], "properties" => {
        "data" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/#{schema_name(resource)}" } }, "meta" => { "$ref" => "#/components/schemas/PageMeta" } } } } } } }
                      .merge(problems(400, 401, 403, 429)) }
  end

  def self.show_operation(resource) = show_operation_for("get#{schema_name(resource)}", "Get one: #{resource.description}", resource.scope, schema_name(resource))

  def self.show_operation_for(id, summary, scope, schema)
    { "operationId" => id, "summary" => summary, "x-required-scope" => scope, "parameters" => [ ref("Id") ],
      "responses" => { "200" => { "description" => "The resource, with its ETag", "headers" => { "ETag" => { "schema" => { "type" => "string" } } }, "content" => { "application/json" => {
        "schema" => { "type" => "object", "required" => %w[data], "properties" => { "data" => { "$ref" => "#/components/schemas/#{schema}" } } } } } },
                       "304" => { "description" => "Not modified (If-None-Match)" } }.merge(problems(401, 403, 404, 429)) }
  end

  def self.entries_list
    filters = Api::V1::Public::EntriesController::FILTERS.keys.map { |name| { "name" => "filter[#{name}]", "in" => "query", "schema" => { "type" => "string" } } }
    sorts = Api::V1::Public::EntriesController::SORTS.keys.flat_map { |name| [ name, "-#{name}" ] }
    { "operationId" => "listEntries", "summary" => "List entries with their lines", "x-required-scope" => "entries:read",
      "parameters" => [ ref("PageSize"), ref("PageAfter"), { "name" => "sort", "in" => "query", "schema" => { "type" => "string", "enum" => sorts } } ] + filters,
      "responses" => { "200" => { "description" => "A page", "content" => { "application/json" => { "schema" => { "type" => "object", "required" => %w[data meta], "properties" => {
        "data" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Entry" } }, "meta" => { "$ref" => "#/components/schemas/PageMeta" } } } } } } }.merge(problems(400, 401, 403, 429)) }
  end

  def self.entry_write(operation_id, summary, scope, status, if_match: false)
    parameters = if_match ? [ ref("Id"), ref("IfMatch") ] : [ ref("IdempotencyKey") ]
    { "operationId" => operation_id, "summary" => summary, "x-required-scope" => scope, "parameters" => parameters,
      "requestBody" => { "required" => true, "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/EntryInput" } } } },
      "responses" => { status.to_s => entry_response }.merge(problems(401, 403, 409, 412, 422, 428, 429)) }
  end

  def self.action(id, summary, scope, status, body: nil)
    operation = { "operationId" => id, "summary" => summary, "x-required-scope" => scope, "parameters" => [ ref("Id"), ref("IdempotencyKey") ],
                  "responses" => { status.to_s => entry_response }.merge(problems(401, 403, 404, 409, 422, 429)) }
    operation["requestBody"] = { "content" => { "application/json" => { "schema" => { "type" => "object", "properties" => body } } } } if body
    operation
  end

  def self.entry_response
    { "description" => "The entry, with its ETag", "headers" => { "ETag" => { "schema" => { "type" => "string" } } }, "content" => { "application/json" => {
      "schema" => { "type" => "object", "required" => %w[data], "properties" => { "data" => { "$ref" => "#/components/schemas/Entry" } } } } } }
  end

  def self.report_operation
    { "operationId" => "getReport", "summary" => "A report as JSON (the Reports::Result of the screens)", "x-required-scope" => "reports:read",
      "parameters" => [ { "name" => "name", "in" => "path", "required" => true, "schema" => { "type" => "string", "enum" => Api::V1::Public::ReportsController::REPORTS } },
                        { "name" => "fiscal_year", "in" => "query", "schema" => { "type" => "integer" } }, { "name" => "as_of", "in" => "query", "schema" => { "type" => "string", "format" => "date" } },
                        { "name" => "kind", "in" => "query", "schema" => { "type" => "string", "enum" => %w[customer supplier] } } ],
      "responses" => { "200" => { "description" => "The report", "content" => { "application/json" => { "schema" => { "type" => "object", "required" => %w[data], "properties" => {
        "data" => { "$ref" => "#/components/schemas/Report" } } } } } } }.merge(problems(401, 403, 404, 429)) }
  end
end
