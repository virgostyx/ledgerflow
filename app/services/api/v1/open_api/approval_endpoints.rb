# The approvals of the public API, as OpenAPI (B01a): what waits for the owner of the token, one request with its circuit, a decision.
# Added to the document by Api::V1::OpenApi. Reading is approvals:read, deciding approvals:decide; both stay within the rights of the owner.
module Api::V1::OpenApi::ApprovalEndpoints
  READ = "approvals:read".freeze
  DECIDE = "approvals:decide".freeze
  NULLABLE_STRING = { "type" => %w[string null] }.freeze
  MONEY = { "type" => "string", "pattern" => '^-?\d+\.\d{2}$' }.freeze
  STATUSES = %w[pending approved rejected changes_requested cancelled invalidated].freeze

  def self.paths
    {
      "/approvals" => { "get" => list },
      "/approvals/{id}" => { "get" => show },
      "/approvals/{id}/decision" => { "post" => decide }
    }
  end

  def self.schemas
    invoice = { "id" => { "type" => "integer" }, "number" => NULLABLE_STRING, "supplier" => { "type" => "string" }, "invoice_date" => { "type" => "string", "format" => "date" },
                "due_date" => { "type" => %w[string null], "format" => "date" }, "currency" => { "type" => "string" }, "amount_incl_vat" => MONEY,
                "amount_eur" => MONEY.merge("description" => "The amount converted at the rate of the invoice, which is what the thresholds of the policies compare.") }
    summary = { "id" => { "type" => "integer" }, "status" => { "type" => "string", "enum" => STATUSES }, "level" => { "type" => "integer" },
                "content_fingerprint" => { "type" => "string", "description" => "SHA-256 of the content put to approval: send it back in the decision, it is what you saw." },
                "submitted_at" => { "type" => %w[string null], "format" => "date-time" }, "created_at" => { "type" => "string", "format" => "date-time" },
                "invoice" => { "type" => "object", "required" => %w[id supplier currency amount_incl_vat amount_eur], "properties" => invoice } }
    {
      "Approval" => { "type" => "object", "required" => %w[id status level content_fingerprint invoice], "properties" => summary },
      "ApprovalDecisionRecord" => { "type" => "object", "required" => %w[decision approver channel decided_at], "properties" => {
        "decision" => { "type" => "string", "enum" => %w[approved rejected changes_requested transferred] }, "approver" => { "type" => "string" }, "on_behalf_of" => NULLABLE_STRING,
        "comment" => NULLABLE_STRING, "channel" => { "type" => "string", "enum" => %w[web mobile api] }, "decided_at" => { "type" => "string", "format" => "date-time" } } },
      "ApprovalLevel" => { "type" => "object", "required" => %w[position mode current decisions], "properties" => {
        "position" => { "type" => "integer" }, "mode" => { "type" => "string", "enum" => %w[any_of all_of] }, "current" => { "type" => "boolean" },
        "decisions" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/ApprovalDecisionRecord" } } } },
      "ApprovalDetail" => { "type" => "object", "required" => %w[id status level content_fingerprint invoice can_decide warnings levels], "properties" => summary.merge(
        "can_decide" => { "type" => "boolean" }, "warnings" => { "type" => "array", "items" => { "type" => "string", "enum" => %w[unusual_amount] } },
        "levels" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/ApprovalLevel" } },
        "invoice" => { "type" => "object", "required" => %w[id supplier currency amount_incl_vat amount_eur lines], "properties" => invoice.merge(
          "lines" => { "type" => "array", "items" => { "type" => "object", "required" => %w[account description amount_incl_vat], "properties" => {
            "account" => { "type" => "string" }, "description" => { "type" => "string" }, "amount_incl_vat" => MONEY } } }) }) },
      "ApprovalDecisionInput" => { "type" => "object", "required" => %w[decision content_fingerprint], "properties" => {
        "decision" => { "type" => "string", "enum" => %w[approved rejected changes_requested] },
        "content_fingerprint" => { "type" => "string", "description" => "The content_fingerprint you read. If the invoice changed since, the answer is 409 content-changed: read it again." },
        "comment" => { "type" => "string", "description" => "Required to refuse and to ask for changes." } } }
    }
  end

  def self.ref(parameter) = Api::V1::OpenApi.ref(parameter)
  def self.problems(*codes) = Api::V1::OpenApi.problems(*codes)
  def self.data(schema) = { "type" => "object", "required" => %w[data], "properties" => { "data" => { "$ref" => "#/components/schemas/#{schema}" } } }

  def self.list
    { "operationId" => "listApprovals", "summary" => "The invoices waiting for the approval of the owner of the token", "x-required-scope" => READ,
      "parameters" => [ ref("PageSize"), ref("PageAfter"), { "name" => "sort", "in" => "query", "schema" => { "type" => "string", "enum" => %w[id -id created_at -created_at] } },
                        { "name" => "filter[supplier]", "in" => "query", "schema" => { "type" => "string" }, "description" => "Part of the name of the supplier." } ],
      "responses" => { "200" => { "description" => "A page of requests", "content" => { "application/json" => { "schema" => { "type" => "object", "required" => %w[data meta], "properties" => {
        "data" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/Approval" } }, "meta" => { "$ref" => "#/components/schemas/PageMeta" } } } } } } }.merge(problems(400, 401, 403, 429, 503)) }
  end

  def self.show
    { "operationId" => "getApproval", "summary" => "One request: the invoice, its lines, the circuit and the decisions taken", "x-required-scope" => READ, "parameters" => [ ref("Id") ],
      "responses" => { "200" => { "description" => "The request, with its ETag", "headers" => { "ETag" => { "schema" => { "type" => "string" } } },
                                  "content" => { "application/json" => { "schema" => data("ApprovalDetail") } } } }.merge(problems(401, 403, 404, 429, 503)) }
  end

  def self.decide
    { "operationId" => "decideApproval", "summary" => "Approve, refuse or ask for changes, on the content you read", "x-required-scope" => DECIDE, "parameters" => [ ref("Id"), ref("IdempotencyKey") ],
      "requestBody" => { "required" => true, "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/ApprovalDecisionInput" } } } },
      "responses" => { "200" => { "description" => "The request after the decision", "content" => { "application/json" => { "schema" => data("ApprovalDetail") } } } }
                       .merge(problems(401, 403, 404, 409, 422, 429, 503)) }
  end
end
