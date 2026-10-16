require "rails_helper"

# B02c, firm side of the thread: read, answer (the clients are told, with no content), turn a client's message into a task. Right: portal.manage.
RSpec.describe "Portal messages (firm side)", type: :request do
  include_context "with entity"

  let(:accountant) { create(:user, full_name: "Alice Accountant").tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:person)     { create(:portal_user, full_name: "Jane Client") }
  let(:thread)     { Portal::MessageThread.of(entity.id) }
  let!(:message)   { thread.messages.create!(entity_id: entity.id, author_kind: "client", portal_user: person, body: "Could you check my VAT?") }

  before do
    Portal::Grant.create!(portal_user: person, entity_id: entity.id, role: "collaborator", capabilities: %w[messages.use])
    ActionMailer::Base.deliveries.clear
    sign_in accountant
  end

  it "shows the thread and marks the messages of the clients as read" do
    get accounting_portal_messages_path

    expect(response.body).to include("Could you check my VAT?", "Jane Client", "not an accounting instruction")
    expect(message.reload.read_by_firm_at).to be_present
  end

  it "answers, and tells the clients without saying what" do
    expect { post accounting_portal_messages_path, params: { body: "Yes, I will." } }.to change(Portal::Message, :count).by(1)

    reply = Portal::Message.order(:id).last
    expect(reply).to have_attributes(author_kind: "firm", user_id: accountant.id, body: "Yes, I will.")
    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ person.email ])
    expect(mail.body.to_s).not_to include("Yes, I will.")
  end

  it "turns a message of a client into a task, once" do
    expect { post convert_accounting_portal_message_path(message) }.to change(Accounting::Task, :count).by(1)
    expect(message.reload.task_id).to be_present
    expect(Accounting::Task.find(message.task_id).description).to include("Could you check my VAT?")

    expect { post convert_accounting_portal_message_path(message) }.not_to change(Accounting::Task, :count)
    expect(Accounting::AuditLog.where(action: "portal_message_converted").count).to eq(1)
  end

  it "refuses an empty answer, and the message of another company" do
    expect { post accounting_portal_messages_path, params: { body: " " } }.not_to change(Portal::Message, :count)
    other = create(:entity)
    foreign = Portal::MessageThread.of(other.id).messages.create!(entity_id: other.id, author_kind: "client", portal_user: person, body: "Foreign")
    expect { post convert_accounting_portal_message_path(foreign) }.not_to change(Accounting::Task, :count)
  end

  it "is for those who manage the portal, and closed while the feature is off" do
    sign_in reader
    expect { post accounting_portal_messages_path, params: { body: "hi" } }.not_to change(Portal::Message, :count)
    sign_in accountant
    entity.update!(features: { "b02c" => false })
    get accounting_portal_messages_path
    expect(response).to redirect_to(accounting_root_path)
  end
end
