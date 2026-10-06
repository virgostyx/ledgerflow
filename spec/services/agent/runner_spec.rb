require "rails_helper"

RSpec.describe Agent::Runner do
  include_context "with entity"

  let(:user) { create(:user) }
  let!(:membership) { create(:user_entity, user: user, entity: entity, role: :accountant) }
  let(:context) { Agent::Context.build(user: user, entity: entity, locale: :en) }
  let(:conversation) { Agent::Conversation.create!(user: user, title: "t") }
  let(:calls) { [] }

  let(:echo) do
    seen = calls
    Class.new(Agent::Tools::Base) do
      tool_name "echo"
      description "Repeats its input."
      permission "reports.view"
      input_schema type: "object", properties: { text: { type: "string" } }, required: %w[text], additionalProperties: false
      define_method(:call) { |args, _ctx| seen << args["text"]; { "data" => args["text"] } }
    end
  end
  let(:registry) { Agent::ToolRegistry.new([ echo ]) }

  def text(string) = Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: string } ], usage: { input_tokens: 100, output_tokens: 10 }, model: "fake-1")
  def tool_use(id, input = { "text" => "hi" }, name: "echo") = Agent::Response.new(stop_reason: "tool_use", content: [ { type: "tool_use", id: id, name: name, input: input } ], usage: { input_tokens: 100, output_tokens: 10 }, model: "fake-1")

  def runner(script, limits: {})
    @gateway = Agent::FakeGateway.new(script)
    described_class.new(conversation: conversation, context: context, gateway: @gateway, registry: registry, limits: limits)
  end

  before do
    entity.update!(features: entity.features.merge("agent" => true))
    Agent::Setting.for_current_entity.update!(enabled: true)
  end

  describe "a question answered without a tool" do
    it "stores the question and the answer, with what the answer cost" do
      answer = runner([ text("Forty-two.") ]).ask("What is the answer?")

      expect(conversation.messages.order(:id).pluck(:role, :content)).to eq([ %w[user What\ is\ the\ answer?], %w[assistant Forty-two.] ])
      expect(answer).to have_attributes(role: "assistant", status: "complete", model: "fake-1", input_tokens: 100, output_tokens: 10)
      expect(answer.latency_ms).to be >= 0
    end

    it "streams the text and says when it is done" do
      events = []
      runner([ text("Forty-two.") ]).ask("Q") { |event| events << event }

      expect(events.map { |e| e[:type] }).to eq(%i[text done])
      expect(events.first[:text]).to eq("Forty-two.")
    end

    it "sends the earlier turns of the talk, then the new question" do
      conversation.messages.create!(role: "user", content: "Hello")
      conversation.messages.create!(role: "assistant", content: "Hi")

      runner([ text("ok") ]).ask("And now?")

      expect(@gateway.requests.first[:messages]).to eq([ { role: "user", content: "Hello" }, { role: "assistant", content: "Hi" }, { role: "user", content: "And now?" } ])
      expect(@gateway.requests.first[:tools]).to eq(registry.definitions)
    end
  end

  describe "a question that needs a tool" do
    it "runs the tool, gives its result back to the model, and answers" do
      events = []
      answer = runner([ tool_use("t1"), text("It said hi.") ]).ask("Echo hi") { |event| events << event }

      expect(calls).to eq([ "hi" ])
      expect(answer.content).to eq("It said hi.")
      second = @gateway.requests.last[:messages]
      expect(second.last).to eq(role: "user", content: [ { type: "tool_result", tool_use_id: "t1", content: { "data" => "hi" }.to_json, is_error: false } ])
      expect(second[-2]).to eq(role: "assistant", content: [ { type: "tool_use", id: "t1", name: "echo", input: { "text" => "hi" } } ])
      expect(events.map { |e| e[:type] }).to eq(%i[tool_start tool_end text done])
      expect(events.find { |e| e[:type] == :tool_end }).to include(name: "echo", error: nil)
    end

    it "gives all the results of one turn back in a single message, in the order of the calls" do
      two = Agent::Response.new(stop_reason: "tool_use", usage: {}, model: "m", content: [ { type: "tool_use", id: "a", name: "echo", input: { "text" => "1" } }, { type: "tool_use", id: "b", name: "echo", input: { "text" => "2" } } ])

      runner([ two, text("done") ]).ask("Q")

      results = @gateway.requests.last[:messages].last[:content]
      expect(results.map { |r| r[:tool_use_id] }).to eq(%w[a b])
    end

    it "tells the model when a tool refused, and flags it as an error" do
      membership.update!(role: :manager)
      allow(echo).to receive(:permission).and_return("agent.configure")

      runner([ tool_use("t1"), text("I cannot see that.") ]).ask("Q")

      result = @gateway.requests.last[:messages].last[:content].first
      expect(result).to include(is_error: true)
      expect(result[:content]).to include("forbidden")
      expect(calls).to be_empty
    end
  end

  describe "the limits of a question" do
    it "stops after the turns it is allowed and says what it could not check" do
      answer = runner([ tool_use("1"), tool_use("2"), tool_use("3") ], limits: { max_turns: 2 }).ask("Q")

      expect(@gateway.requests.size).to eq(2)
      expect(answer.content).to include("limit")
      expect(answer.status).to eq("complete")
    end

    it "stops after the tool calls it is allowed" do
      answer = runner([ tool_use("1"), tool_use("2") ], limits: { max_tool_calls: 1 }).ask("Q")

      expect(calls.size).to eq(1)
      expect(answer.content).to include("limit")
    end

    it "stops when the time is up, before asking the model anything" do
      answer = runner([ text("never") ], limits: { max_seconds: 0 }).ask("Q")

      expect(@gateway.requests).to be_empty
      expect(answer.content).to include("limit")
    end

    it "gives up after three tool errors in a row and explains" do
      script = Array.new(4) { |i| tool_use(i.to_s, {}, name: "missing") } + [ text("never") ]

      answer = runner(script).ask("Q")

      expect(@gateway.requests.size).to eq(3)
      expect(answer.content).to include("tools are not answering")
    end
  end

  describe "stopping" do
    it "runs nothing after the person pressed stop, and keeps what was said as a stopped answer" do
      stop = -> { @gateway.requests.size >= 1 }

      answer = runner([ tool_use("1"), text("never") ]).ask("Q", stop: stop)

      expect(calls).to be_empty
      expect(answer.status).to eq("stopped")
      expect(@gateway.requests.size).to eq(1)
    end
  end

  describe "the rights, checked all along" do
    it "refuses to start when the agent is off" do
      Agent::Setting.for_current_entity.update!(enabled: false)

      expect { runner([ text("x") ]).ask("Q") }.to raise_error(Agent::Unavailable) { |e| expect(e.reason).to eq(:not_enabled) }
      expect(conversation.messages).to be_empty
    end

    it "stops asking the model once the right was taken away during the answer" do
      taker = Class.new(echo) { def call(*) = (UserEntity.find_by(role: :accountant).update!(role: :auditor, valid_until: 1.month.from_now); { "data" => "x" }) }
      taking = described_class.new(conversation: conversation, context: context, gateway: (@gateway = Agent::FakeGateway.new([ tool_use("1"), text("never") ])), registry: Agent::ToolRegistry.new([ taker ]))
      membership # the accountant, who may use the agent

      answer = taking.ask("Q")

      expect(@gateway.requests.size).to eq(1)
      expect(answer.content).to include("no longer")
    end
  end
end
