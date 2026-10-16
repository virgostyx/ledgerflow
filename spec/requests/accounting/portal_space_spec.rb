require "rails_helper"

RSpec.describe "Portal space (firm side)", type: :request do
  include_context "with entity"
  include DocumentFiles

  let(:accountant) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:reader)     { create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) } }
  let(:jane)       { create(:portal_user, full_name: "Jane Client") }

  before { sign_in accountant }

  it "gathers what the clients sent, what waits for them, the publications and the people who do not come" do
    Portal::Grant.create!(portal_user: jane, entity_id: entity.id, role: "director", capabilities: %w[questions.answer])
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("lately")), filename: "lately.pdf", user: nil, origin: :portal)
    Accounting::UploadDocument.call(io: StringIO.new(sample_pdf("by hand")), filename: "by-hand.pdf", user: accountant)
    Portal::Question.create!(entity_id: entity.id, task_id: 1, title: "Is it professional?", answer_type: "text", asked_at: 3.days.ago, asked_by_id: accountant.id)
    PortalAdmin::Publish.call(entity: entity, kind: "other", title: "Situation", files: [ { filename: "a.pdf", content_type: "application/pdf", data: "%PDF" } ], by: accountant)

    get accounting_portal_space_path

    expect(response.body).to include("lately.pdf", "Is it professional?", "Situation", "Jane Client", "no approval asked")
    expect(response.body).not_to include("by-hand.pdf")
  end

  it "does not show another company's questions" do
    Portal::Question.create!(entity_id: create(:entity).id, task_id: 1, title: "Foreign question", answer_type: "text", asked_at: 1.day.ago, asked_by_id: accountant.id)
    get accounting_portal_space_path
    expect(response.body).not_to include("Foreign question")
  end

  it "is for those who manage the portal" do
    sign_in reader
    get accounting_portal_space_path
    expect(response.body).not_to include("Questions waiting")
  end
end
