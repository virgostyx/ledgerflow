require "rails_helper"

# A03: what a person tells the agent, and what it answers, does not end up in the application's logs.
RSpec.describe "The agent and the logs (A03)", type: :request do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let(:secret_question) { "Pay BE68539007547034 with key sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 please" }

  before do
    entity.update!(features: entity.features.merge("agent" => true))
    Agent::Setting.for_current_entity.update!(enabled: true)
    accept_agent_consent!
    sign_in accountant
  end

  it "filters the question and the comment out of the request parameters" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter("question" => secret_question, "comment" => "private remark", "rating" => "useful")

    expect(filtered).to eq("question" => "[FILTERED]", "comment" => "[FILTERED]", "rating" => "useful")
  end

  it "keeps the question out of the log of the job that answers it" do
    io = StringIO.new
    previous = ActiveJob::Base.logger
    ActiveJob::Base.logger = ActiveSupport::Logger.new(io)
    conversation = Agent::Conversation.create!(user: accountant, title: "t")

    Agent::AnswerJob.perform_later(conversation, secret_question, "en")

    expect(io.string).to include("Agent::AnswerJob")
    expect(io.string).not_to match(/BE68539007547034|sk-ant/)
  ensure
    ActiveJob::Base.logger = previous
  end

  it "keeps the question and the answer out of the log while it is answered" do
    io = StringIO.new
    previous = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    conversation = Agent::Conversation.create!(user: accountant, title: "t")
    allow(Agent::ModelGateway).to receive(:default).and_return(Agent::FakeGateway.new([ Agent::Response.new(stop_reason: "end_turn", content: [ { type: "text", text: "IBAN BE68539007547034" } ], usage: {}, model: "m") ]))
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    Agent::AnswerJob.perform_now(conversation, secret_question, "en")

    expect(io.string).not_to match(/BE68539007547034|sk-ant/)
  ensure
    Rails.logger = previous
  end
end
