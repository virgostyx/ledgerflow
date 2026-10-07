# The version of the agent, as a hash of what makes it behave (A12): its instructions, its tool catalog (names, descriptions and schemas: what steers the model's choice), the models
# of its tasks and its masking. Each answer carries the hash, so that an answer can be put back in the version that gave it, and the evaluation can say which version it measured.
class Agent::Manifest
  MASKING_SOURCES = %w[redactor identifiers sensitive_input injection_detector response_guard untrusted].freeze

  Version = Data.define(:components) do
    def hash_value = Agent::Manifest.digest(components.sort.to_h.to_json)
  end

  def self.current
    Version.new(components: {
      "system_prompt" => digest(File.read(Agent::SystemPrompt::PRINCIPLES)),
      "tools" => digest(Agent::ToolRegistry.default.definitions.to_json),
      "models" => digest(Agent::Config.settings[:models].to_json),
      "masking" => digest(MASKING_SOURCES.map { |name| File.read(Rails.root.join("app/services/agent/#{name}.rb")) }.join + Agent::Setting::DEFAULT_MODES.to_json)
    })
  end

  def self.digest(text) = Digest::SHA256.hexdigest(text)[0, 16]
end
