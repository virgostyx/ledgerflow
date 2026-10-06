# Answers a question in the background and shows it as it is written (A01): the text streams into the live bubble of the panel through Turbo Streams, the
# finished message replaces it. The panel never calls the model itself; a stop request is read between two steps of the runner.
class Agent::AnswerJob < ApplicationJob
  queue_as :agent_interactive

  def perform(conversation, question, locale)
    ActsAsTenant.with_tenant(conversation.entity) do
      conversation.clear_stop!
      context = Agent::Context.build(user: conversation.user, entity: conversation.entity, locale: locale, screen: conversation.origin_screen, subject_ref: conversation.context_ref)
      runner = Agent::Runner.new(conversation: conversation, context: context)
      runner.ask(question, stop: -> { conversation.stop_requested? }) { |event| show(conversation, event) }
    end
  rescue Agent::Unavailable => e
    notice(conversation, e.reason)
  rescue StandardError => e
    Rails.logger.error("[agent] answer failed: #{e.class}")
    notice(conversation, :failed)
  end

  private

  def show(conversation, event)
    case event[:type]
    when :text       then Turbo::StreamsChannel.broadcast_append_to(conversation, target: dom(conversation, "live_text"), html: ERB::Util.html_escape(event[:text]).to_s)
    when :tool_start then Turbo::StreamsChannel.broadcast_append_to(conversation, target: dom(conversation, "live_steps"), partial: "agent/messages/step", locals: { name: event[:name] })
    when :done       then Turbo::StreamsChannel.broadcast_replace_to(conversation, target: dom(conversation, "live"), partial: "agent/messages/message", locals: { message: event[:message] })
    end
  end

  def notice(conversation, reason)
    Turbo::StreamsChannel.broadcast_replace_to(conversation, target: dom(conversation, "live"), partial: "agent/messages/notice", locals: { reason: reason })
  end

  def dom(conversation, part) = "agent_conversation_#{conversation.id}_#{part}"
end
