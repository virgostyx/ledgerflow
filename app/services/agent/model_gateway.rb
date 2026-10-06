# The only place that calls the language model (A01, A04). It picks the model of the task, applies the timeouts, streams the text and gives back an
# Agent::Response. Outside production it refuses unless AGENT_ALLOW_LIVE_PROVIDER is set. The Redactor of A04 will work here, just before the call.
class Agent::ModelGateway
  def self.default
    live_allowed? ? new : Agent::FakeGateway.simulated
  end

  def self.live_allowed? = Rails.env.production? || ENV["AGENT_ALLOW_LIVE_PROVIDER"].present?

  def initialize(client: nil)
    @client = client
  end

  def call(system:, messages:, tools:, task: :chat_default, &on_text)
    raise Agent::LiveProviderRefused unless self.class.live_allowed?

    params = { model: Agent::Config.model_for(task), max_tokens: Agent::Config.provider.fetch(:max_tokens), system_: system, messages: messages }
    params[:tools] = tools if tools.any?
    stream = client.messages.stream(**params)
    stream.text.each { |piece| on_text&.call(piece) }
    message = stream.accumulated_message

    Agent::Response.new(stop_reason: message.stop_reason.to_s, content: message.content.map(&:to_h),
                        usage: { input_tokens: message.usage.input_tokens, output_tokens: message.usage.output_tokens }, model: message.model.to_s)
  end

  private

  # The key lives in the credentials (anthropic.api_key) or in ANTHROPIC_API_KEY; it is never in the repository.
  def client
    @client ||= Anthropic::Client.new(api_key: Rails.application.credentials.dig(:anthropic, :api_key) || ENV["ANTHROPIC_API_KEY"],
                                      timeout: Agent::Config.provider.fetch(:timeout_seconds), max_retries: Agent::Config.provider.fetch(:max_retries))
  end
end
