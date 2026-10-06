require "rails_helper"

RSpec.describe Agent::AnswerJob do
  include_context "with entity"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, user: user, entity: entity, role: :accountant) }
  let(:conversation) { Agent::Conversation.create!(user: user, title: "t") }
  let(:sent) { [] }

  def reply(text) = Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: text } ], usage: { input_tokens: 1, output_tokens: 1 }, model: "fake")

  before do
    entity.update!(features: entity.features.merge("agent" => true))
    Agent::Setting.for_current_entity.update!(enabled: true)
    accept_agent_consent!
    %i[broadcast_append_to broadcast_replace_to].each do |method|
      allow(Turbo::StreamsChannel).to receive(method) { |_stream, **opts| sent << [ method, opts ] }
    end
  end

  def run_with(script) = (allow(Agent::ModelGateway).to receive(:default).and_return(Agent::FakeGateway.new(script)); described_class.perform_now(conversation, "Question?", "en"))

  it "answers, streaming the text into the live bubble and replacing it by the finished message" do
    run_with([ reply("Forty-two.") ])

    appended = sent.select { |method, _| method == :broadcast_append_to }.map { |_, o| o }
    replaced = sent.select { |method, _| method == :broadcast_replace_to }.map { |_, o| o }
    expect(appended.map { |o| o[:html] }).to include("Forty-two.")
    expect(appended.first[:target]).to eq("agent_conversation_#{conversation.id}_live_text")
    expect(replaced.last).to include(target: "agent_conversation_#{conversation.id}_live", partial: "agent/messages/message")
    expect(conversation.messages.order(:id).pluck(:role)).to eq(%w[user assistant])
  end

  it "streams the names back in: the person reads the answer as it is, the model only had tokens" do
    create(:partner, name: "Alice Dupont", is_natural_person: true, city: "Namur")
    search = Agent::Response.new(stop_reason: "tool_use", usage: {}, model: "m", content: [ { type: "tool_use", id: "1", name: "search_partners", input: { "q" => "Namur" } } ])

    run_with([ search, reply("PERSONNE_001 lives in Namur.") ])

    streamed = sent.select { |method, _| method == :broadcast_append_to }.map { |_, o| o[:html] }
    expect(streamed).to include("Alice Dupont lives in Namur.")
  end

  it "escapes what it streams: the text of the model is never markup" do
    run_with([ reply("<script>x</script>") ])

    streamed = sent.select { |method, _| method == :broadcast_append_to }.map { |_, o| o[:html] }
    expect(streamed.join).not_to include("<script>")
  end

  it "says the agent is unavailable, without detail, when it was switched off after the question was sent" do
    Agent::Setting.for_current_entity.update!(enabled: false)

    run_with([ reply("never") ])

    expect(sent.last[1]).to include(partial: "agent/messages/notice", locals: { reason: :not_enabled })
    expect(conversation.messages).to be_empty
  end

  it "says that something went wrong, and logs it, when the provider fails" do
    allow(Agent::ModelGateway).to receive(:default).and_return(Class.new { def call(**) = raise("boom: secret detail") }.new)
    allow(Rails.logger).to receive(:error)

    described_class.perform_now(conversation, "Question?", "en")

    expect(sent.last[1]).to include(partial: "agent/messages/notice", locals: { reason: :failed })
    expect(Rails.logger).to have_received(:error).with(/RuntimeError/)
    expect(sent.to_s).not_to include("secret detail")
  end

  it "starts from a clean slate: a stop requested before the question does not cancel it" do
    conversation.request_stop!

    run_with([ reply("first") ])

    expect(conversation.messages.last.status).to eq("complete")
  end

  it "is no longer 'answering' once it is over, whatever happened" do
    conversation.start_answering!
    allow(Agent::ModelGateway).to receive(:default).and_return(Class.new { def call(**) = raise("boom") }.new)

    described_class.perform_now(conversation, "Question?", "en")

    expect(conversation.reload.answering_since).to be_nil
  end

  it "runs in the interactive queue, which batches never wait behind" do
    expect(described_class.new.queue_name).to eq("agent_interactive")
  end
end
