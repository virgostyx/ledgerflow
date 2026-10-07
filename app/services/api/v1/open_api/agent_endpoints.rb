# The agent's endpoints of the public API, as OpenAPI (A01): conversations, a question (202, answered in the background), an opinion on an answer. Added to the document by Api::V1::OpenApi;
# the scope of every operation is agent:use.
module Api::V1::OpenApi::AgentEndpoints
  SCOPE = "agent:use".freeze
  NULLABLE_STRING = { "type" => %w[string null] }.freeze

  def self.paths
    {
      "/agent/conversations" => { "get" => list, "post" => create },
      "/agent/conversations/{id}" => { "get" => show, "patch" => update, "delete" => destroy },
      "/agent/conversations/{id}/stop" => { "post" => stop },
      "/agent/conversations/{id}/messages" => { "post" => ask },
      "/agent/conversations/{id}/messages/{message_id}/feedback" => { "post" => rate }
    }
  end

  def self.parameters = { "MessageId" => { "name" => "message_id", "in" => "path", "required" => true, "schema" => { "type" => "integer" } } }

  def self.schemas
    conversation = { "id" => { "type" => "integer" }, "title" => NULLABLE_STRING, "status" => { "type" => "string", "enum" => %w[active archived] }, "origin_screen" => NULLABLE_STRING,
                     "answering" => { "type" => "boolean", "description" => "True while an answer is being written: read the conversation again until it is false." },
                     "created_at" => { "type" => "string", "format" => "date-time" }, "updated_at" => { "type" => "string", "format" => "date-time" } }
    required = %w[id status answering created_at updated_at]
    {
      "AgentConversation" => { "type" => "object", "required" => required, "properties" => conversation },
      "AgentMessage" => { "type" => "object", "required" => %w[id role content status flags created_at], "properties" => {
        "id" => { "type" => "integer" }, "role" => { "type" => "string", "enum" => %w[user assistant] }, "content" => { "type" => "string", "description" => "Plain text with Markdown; names are the real ones." },
        "status" => { "type" => "string", "enum" => %w[complete stopped failed] }, "flags" => { "type" => "array", "items" => { "type" => "string" } }, "created_at" => { "type" => "string", "format" => "date-time" } } },
      "AgentConversationDetail" => { "type" => "object", "required" => required + [ "messages" ], "properties" => conversation.merge("messages" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/AgentMessage" } }) },
      "AgentConversationInput" => { "type" => "object", "properties" => { "conversation" => { "type" => "object", "properties" => {
        "screen" => { "type" => "string", "maxLength" => 80 }, "subject_type" => { "type" => "string", "maxLength" => 60 }, "subject_id" => { "type" => "string", "maxLength" => 60 } } } } },
      "AgentConversationUpdate" => { "type" => "object", "properties" => { "title" => { "type" => "string", "maxLength" => 120 }, "archived" => { "type" => "boolean" } } },
      "AgentQuestionInput" => { "type" => "object", "required" => %w[question], "properties" => { "question" => { "type" => "string", "maxLength" => Agent::MessagesController::MAX_LENGTH },
                                                                                               "confirm_sensitive" => { "type" => "boolean", "description" => "Send anyway what the entity lets go, once the 422 sensitive-data was read." } } },
      "AgentAccepted" => { "type" => "object", "required" => %w[conversation_id status], "properties" => { "conversation_id" => { "type" => "integer" }, "status" => { "type" => "string", "enum" => %w[answering] } } },
      "AgentFeedbackInput" => { "type" => "object", "required" => %w[rating], "properties" => { "rating" => { "type" => "string", "enum" => %w[useful not_useful] },
                                                                                               "category" => { "type" => "string", "enum" => Agent::Feedback::CATEGORIES }, "comment" => { "type" => "string" } } },
      "AgentFeedbackResult" => { "type" => "object", "required" => %w[message_id rating], "properties" => { "message_id" => { "type" => "integer" }, "rating" => { "type" => "string" }, "category" => NULLABLE_STRING } }
    }
  end

  def self.ref(parameter) = Api::V1::OpenApi.ref(parameter)
  def self.problems(*codes) = Api::V1::OpenApi.problems(*codes)
  def self.data(schema) = { "type" => "object", "required" => %w[data], "properties" => { "data" => { "$ref" => "#/components/schemas/#{schema}" } } }
  def self.json_body(schema) = { "required" => true, "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/#{schema}" } } } }
  def self.ok(description, schema, status: "200", headers: {}) = { status => { "description" => description, "headers" => headers, "content" => { "application/json" => { "schema" => data(schema) } } }.compact_blank }

  def self.list
    { "operationId" => "listAgentConversations", "summary" => "List your conversations with the assistant", "x-required-scope" => SCOPE,
      "parameters" => [ ref("PageSize"), ref("PageAfter"), { "name" => "sort", "in" => "query", "schema" => { "type" => "string", "enum" => %w[id -id updated_at -updated_at] } },
                        { "name" => "filter[status]", "in" => "query", "schema" => { "type" => "string", "enum" => %w[active archived] } } ],
      "responses" => { "200" => { "description" => "A page of your conversations, most recently used first", "content" => { "application/json" => { "schema" => { "type" => "object", "required" => %w[data meta], "properties" => {
        "data" => { "type" => "array", "items" => { "$ref" => "#/components/schemas/AgentConversation" } }, "meta" => { "$ref" => "#/components/schemas/PageMeta" } } } } } } }.merge(problems(400, 401, 403, 429, 503)) }
  end

  def self.create
    { "operationId" => "createAgentConversation", "summary" => "Open a conversation with the assistant", "x-required-scope" => SCOPE, "requestBody" => { "content" => { "application/json" => { "schema" => { "$ref" => "#/components/schemas/AgentConversationInput" } } } },
      "responses" => ok("The conversation", "AgentConversation", status: "201", headers: { "Location" => { "schema" => { "type" => "string" } } }).merge(problems(401, 403, 422, 429, 503)) }
  end

  def self.show
    { "operationId" => "getAgentConversation", "summary" => "Read a conversation with what was said in it", "x-required-scope" => SCOPE, "parameters" => [ ref("Id") ],
      "responses" => ok("The conversation and its messages, with its ETag", "AgentConversationDetail", headers: { "ETag" => { "schema" => { "type" => "string" } } }).merge(problems(401, 403, 404, 429, 503)) }
  end

  def self.update
    { "operationId" => "updateAgentConversation", "summary" => "Rename or archive a conversation (If-Match required)", "x-required-scope" => SCOPE, "parameters" => [ ref("Id"), ref("IfMatch") ],
      "requestBody" => json_body("AgentConversationUpdate"), "responses" => ok("The conversation", "AgentConversation").merge(problems(401, 403, 404, 412, 428, 429, 503)) }
  end

  def self.destroy
    { "operationId" => "deleteAgentConversation", "summary" => "Delete a conversation and what was said in it", "x-required-scope" => SCOPE, "parameters" => [ ref("Id") ],
      "responses" => { "204" => { "description" => "Deleted" } }.merge(problems(401, 403, 404, 429, 503)) }
  end

  def self.stop
    { "operationId" => "stopAgent", "summary" => "Stop what the assistant is writing", "x-required-scope" => SCOPE, "parameters" => [ ref("Id") ],
      "responses" => { "204" => { "description" => "The stop was recorded: nothing runs after it" } }.merge(problems(401, 403, 404, 429, 503)) }
  end

  def self.ask
    { "operationId" => "askAgent", "summary" => "Put a question to the assistant: accepted, answered in the background", "x-required-scope" => SCOPE, "parameters" => [ ref("Id"), ref("IdempotencyKey") ],
      "requestBody" => json_body("AgentQuestionInput"),
      "responses" => ok("Accepted: read the conversation until it is no longer answering", "AgentAccepted", status: "202", headers: { "Location" => { "schema" => { "type" => "string" } } }).merge(problems(401, 403, 404, 422, 429, 503)) }
  end

  def self.rate
    { "operationId" => "rateAgentAnswer", "summary" => "Say whether an answer was useful", "x-required-scope" => SCOPE, "parameters" => [ ref("Id"), ref("MessageId") ],
      "requestBody" => json_body("AgentFeedbackInput"), "responses" => ok("The opinion recorded", "AgentFeedbackResult", status: "201").merge(problems(401, 403, 404, 422, 429, 503)) }
  end
end
