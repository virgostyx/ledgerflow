# The agent's settings from config/agent.yml: which model for which task, the limits of a question, the provider's timeouts.
module Agent::Config
  def self.settings = (@settings ||= Rails.application.config_for(:agent))
  def self.reset! = @settings = nil

  def self.model_for(task) = settings.fetch(:models).fetch(task.to_sym)
  def self.limits = settings.fetch(:limits)
  def self.provider = settings.fetch(:provider)
end
