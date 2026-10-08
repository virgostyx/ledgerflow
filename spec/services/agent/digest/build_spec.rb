require "rails_helper"

# A10a: the summary is built from the facts, without a model, with the rights of its recipient; only what changed or is urgent; nothing when there is nothing.
RSpec.describe Agent::Digest::Build do
  include_context "with_open_fiscal_year"

  let(:accountant) { create(:user) }
  let(:reader) { create(:user) }
  let!(:membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:reader_membership) { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:today) { Date.new(2026, 9, 30) }

  before do
    enable_agent!
    allow(Agent::ModelGateway).to receive(:new).and_raise("the summary must not call the model")
    allow(Agent::ModelGateway).to receive(:default).and_raise("the summary must not call the model")
  end

  def build(user = accountant, **options) = described_class.call(user: user, entity: entity, today: today, **options)

  def finding(severity: "blocking", fingerprint: SecureRandom.hex(4), run: nil)
    run ||= Accounting::ConsistencyRun.latest_first.first || Accounting::ConsistencyRun.create!(trigger: "spec", started_at: Time.current)
    run.findings.create!(entity: entity, check_id: "C04", severity: severity, fingerprint: fingerprint, message: "Account 440000 has a debit balance", subject_type: "Accounting::Account", subject_id: 1)
  end

  def items(digest) = digest.sections.flat_map { |section| section["items"] }

  it "builds nothing when there is nothing to say" do
    expect(build).to be_nil
    expect(Agent::Digest.count).to eq(0)
  end

  it "says what is open among the anomalies, in counts, with a link to the screen" do
    finding(severity: "blocking")
    finding(severity: "warning")

    digest = build

    expect(digest).to have_attributes(kind: "scheduled", item_count: 1, local_date: today)
    expect(items(digest).first).to include("key" => "anomalies", "text" => "1 blocking and 1 other anomalies are open, 2 new since the last summary.", "urgent" => true)
    expect(Agent::Refs.path(items(digest).first["ref"])).to eq(Agent::Screens.path("consistency"))
  end

  it "gives the same figures as the read tool for the same person" do
    3.times { finding(severity: "warning") }
    finding(severity: "blocking")
    registry = Agent::ToolRegistry.default
    context = Agent::Context.build(user: accountant, entity: entity, locale: :en)

    from_tool = registry.execute("get_consistency_findings", {}, context)["totals"].except("ref").values.sum(&:to_i)

    expect(items(build).first["count"]).to eq(from_tool)
  end

  it "does not repeat what did not change and is not urgent, and repeats what is urgent" do
    finding(severity: "warning", fingerprint: "w1")
    expect(build).to be_present

    expect(build).to be_nil # the same warning, not urgent: no new summary

    finding(severity: "blocking", fingerprint: "b1")
    expect(build).to be_present
    expect(build).to be_present # a blocking anomaly still open is told again
  end

  it "says when a new anomaly appears since the last summary" do
    finding(severity: "warning", fingerprint: "w1")
    build
    finding(severity: "warning", fingerprint: "w2")

    expect(items(build).first["text"]).to include("1 new since the last summary")
  end

  it "leaves out an anomaly that somebody acknowledged" do
    one = finding(severity: "blocking", fingerprint: "ack")
    Accounting::ConsistencyAcknowledgement.create!(fingerprint: one.fingerprint, comment: "Known", user: accountant, acknowledged_at: Time.current)

    expect(build).to be_nil
  end

  it "reports the documents waiting in the inbox, the tasks overdue and the bank lines pending, each with its own counts" do
    create(:document)
    Accounting::Task.create!(title: "Call", kind: :other, status: :open, assignee: accountant, author: accountant, due_on: today - 3)

    digest = build

    texts = items(digest).map { |item| item["text"] }
    expect(texts).to include("1 document(s) wait in the inbox.", "1 of your task(s) are overdue.")
  end

  it "shows a person only the tasks that are theirs" do
    Accounting::Task.create!(title: "Call", kind: :other, status: :open, assignee: accountant, author: accountant, due_on: today - 3)

    expect(build(reader)).to be_nil
  end

  it "builds with the rights of the recipient: a reader does not get the bank nor the received invoices" do
    create(:document)
    Accounting::PeppolMessage.create!(entity: entity, direction: :inbound, document_type: :invoice, status: :needs_review, message_id: "m1", occurred_at: Time.current)

    expect(items(build(reader)).map { |item| item["key"] }).to eq([ "documents" ])
    expect(items(build(accountant)).map { |item| item["key"] }).to include("documents", "peppol")
  end

  it "puts the most urgent first and at most ten points" do
    finding(severity: "blocking")
    create(:document)

    expect(items(build).first["key"]).to eq("anomalies")
    expect(Agent::Digest::MAX_ITEMS).to eq(10)
  end

  it "keeps what the person chose: only the sections they ticked" do
    finding(severity: "blocking")
    create(:document)

    expect(items(build(sections: [ "documents" ])).map { |item| item["key"] }).to eq([ "documents" ])
  end

  it "keeps the content encrypted" do
    finding(severity: "blocking")
    digest = build

    expect(ActiveRecord::Base.connection.select_value("SELECT payload FROM agent_digests WHERE id = #{digest.id}")).not_to include("anomalies")
  end

  it "says a VAT return is due when the period has ended, the next one after the last declaration" do
    fy = fiscal_year
    Accounting::VatDeclaration.create!(entity: entity, fiscal_year: fy, period_type: :quarterly, period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 3, 31), status: 0, grids: {})
    # the quarter April-June ended, the return is due on 20 July: overdue on 30 September
    digest = build

    expect(items(digest).first).to include("key" => "vat", "text" => "A VAT return is overdue.", "urgent" => true)
  end

  it "does nothing for a person who cannot use the assistant" do
    Agent::Setting.for_current_entity.update!(enabled: false)
    finding

    expect(build).to be_nil
  end
end
