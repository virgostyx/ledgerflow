require "rails_helper"

# F08 §11, criterion 5: the link of a third party answers until the date planned, and gives access to nothing else. The question, the answer in text and
# files (to the document inbox), the people concerned told, a refusal that looks the same whatever its cause.
RSpec.describe "A third party answers a question (F08)", type: :request do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"
  include ActiveJob::TestHelper

  let(:accountant) { create(:user, role: :accountant, email: "alice@firm.test", full_name: "Alice Accountant") }
  let(:assistant)  { create(:user, role: :auditor, email: "anna@firm.test", full_name: "Anna Assistant") }
  let(:reader)     { create(:user, role: :manager) }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let(:partner) { create(:partner, :supplier, name: "Secret Partner SA") }
  let!(:task) do
    Accounting::CreateTask.call(user: accountant, title: "Internal title", description: "Internal notes: do not show", target: partner, assignee: assistant)[:task]
  end

  def issue(days: 14, question: "What is this payment of 500 euros for?", user: accountant) = Accounting::IssueExternalLink.call(task: task, user: user, question: question, days: days)
  def token = task.reload.external_link_token

  describe "issuing the link" do
    it "gives a signed link that ends at the end of the day planned, and turns the task into a question to a third party" do
      result = issue(days: 10)

      expect(result).to be_success
      expect(task.reload).to have_attributes(kind: "client_question", question: "What is this payment of 500 euros for?")
      expect(task.external_expires_at).to be_within(1.minute).of(10.days.from_now.end_of_day)
      expect(Accounting::Task.find_by_external_token(token)).to eq(task)
      expect(Accounting::AuditLog.where(action: "task_external_link_issued", auditable_id: task.id)).to exist
    end

    it "needs the right to change the task, a question, and keeps the term within sixty days" do
      expect(issue(user: reader)).to be_failure
      expect(issue(question: " ")).to be_failure
      issue(days: 5_000)
      expect(task.reload.external_expires_at).to be < 61.days.from_now
    end

    it "is made from the task screen, shown there, and ended at once on request" do
      sign_in accountant
      post external_link_accounting_task_path(task), params: { question: "Who is this?", days: 7 }
      get accounting_task_path(task)
      expect(response.body).to include(external_reply_url(token: token)).and include("End the link now")

      post revoke_external_link_accounting_task_path(task)
      expect(Accounting::Task.find_by_external_token(task.signed_id(purpose: :external_reply))).to be_nil
      expect(Accounting::AuditLog.where(action: "task_external_link_revoked", auditable_id: task.id)).to exist
    end
  end

  describe "the link" do
    before { issue }

    it "answers before its date, not after, not once revoked, not when changed, not for another purpose" do
      good = token
      expect(Accounting::Task.find_by_external_token(good)).to eq(task)

      expect(Accounting::Task.find_by_external_token(good + "x")).to be_nil
      expect(Accounting::Task.find_by_external_token(task.signed_id(purpose: :something_else))).to be_nil
      expect(Accounting::Task.find_by_external_token(task.id.to_s)).to be_nil

      travel_to(15.days.from_now) { expect(Accounting::Task.find_by_external_token(good)).to be_nil }

      Accounting::RevokeExternalLink.call(task: task, user: accountant)
      expect(Accounting::Task.find_by_external_token(good)).to be_nil
    end

    it "does not open another task" do
      other = Accounting::CreateTask.call(user: accountant, title: "Other", target: partner)[:task]
      Accounting::IssueExternalLink.call(task: other, user: accountant, question: "Other question?")

      get external_reply_path(token: other.external_link_token)
      expect(response.body).to include("Other question?").and not_include("What is this payment")
    end
  end

  describe "the public page" do
    before do
      issue
      Accounting::AddComment.call(commentable: task, user: accountant, body: "Internal comment, private")
    end

    it "shows the question and the name of the entity, and nothing else of the task or of the books (criterion 5)" do
      get external_reply_path(token: token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("What is this payment of 500 euros for?").and include(entity.legal_name)
      %w[Internal\ title Internal\ notes Internal\ comment Secret\ Partner].each { |hidden| expect(response.body).not_to include(hidden) }
    end

    it "does not let the link leave in a Referer, nor be indexed" do
      get external_reply_path(token: token)

      expect(response.headers["Referrer-Policy"]).to eq("no-referrer")
      expect(response.headers["X-Robots-Tag"]).to include("noindex")
    end

    it "does not answer when the feature is off for the entity" do
      good = token
      entity.update!(features: { "f08" => false })

      get external_reply_path(token: good)

      expect(response).to have_http_status(:not_found)
    end

    it "needs no account" do
      get external_reply_path(token: token)

      expect(response).not_to redirect_to(new_user_session_path)
    end

    it "looks the same whatever is wrong with the link: not valid, expired or ended" do
      good = token
      get external_reply_path(token: "nonsense")
      invalid = [ response.status, response.body ]
      travel_to(15.days.from_now) { get external_reply_path(token: good) }
      expired = [ response.status, response.body ]

      expect(invalid).to eq(expired)
      expect(invalid.first).to eq(404)
      expect(invalid.last).to include("not valid, or it has expired")
    end
  end

  describe "the answer" do
    before { issue }

    def reply(params = {}, files = [])
      post external_reply_path(token: token), params: { name: "Mr Client", body: "It is the deposit of the order 12", **params, files: files.presence }.compact
    end

    it "becomes a comment of the thread with no author, and tells the author and the assignee, once each" do
      expect { reply }.to change(Accounting::Comment, :count).by(1)

      comment = Accounting::Comment.last
      expect(comment).to have_attributes(author_id: nil, external_name: "Mr Client", body: "It is the deposit of the order 12", commentable: task)
      expect(response.body).to include("Thank you")
      expect(Accounting::Notification.where(event: "external_reply").pluck(:user_id)).to match_array([ accountant.id, assistant.id ])
      expect(Accounting::AuditLog.where(action: "task_external_reply", auditable_id: task.id).sole.ip_address).to be_present
    end

    it "shows in the thread of the task, marked as coming from outside" do
      reply
      sign_in accountant

      get accounting_task_path(task)

      expect(response.body).to include("Mr Client (outside)").and include("deposit of the order 12")
    end

    it "takes files to the document inbox, which are checked like any upload, and says which were not accepted" do
      pdf = Rack::Test::UploadedFile.new(StringIO.new(sample_pdf("Contract")), "application/pdf", original_filename: "contract.pdf")
      bad = Rack::Test::UploadedFile.new(StringIO.new("MZ\x90\x00 an executable"), "application/octet-stream", original_filename: "tool.exe")

      expect { reply({ body: "" }, [ pdf, bad ]) }.to change(Accounting::Document, :count).by(1)

      expect(Accounting::Document.last).to have_attributes(origin: "external_reply", name: "contract.pdf", status: "inbox")
      expect(Accounting::Document.last.extracted_data).to include("task_id" => task.id, "external_name" => "Mr Client")
      expect(response.body).to include("Not accepted").and include("tool.exe")
      expect(Accounting::Comment.last.body).to include("contract.pdf").and include("tool.exe")
    end

    it "keeps three files at most" do
      files = Array.new(4) { |i| Rack::Test::UploadedFile.new(StringIO.new(sample_pdf("File #{i}")), "application/pdf", original_filename: "f#{i}.pdf") }

      expect { reply({}, files) }.to change(Accounting::Document, :count).by(3)
    end

    it "asks for a name, and for an answer or a file, and for a reasonable length" do
      expect { reply({ name: "" }) }.not_to change(Accounting::Comment, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect { reply({ body: "" }) }.not_to change(Accounting::Comment, :count)
      expect { reply({ body: "x" * 5_001 }) }.not_to change(Accounting::Comment, :count)
    end

    it "is refused once the link has ended, and nothing is kept" do
      url = external_reply_path(token: token)
      travel_to(15.days.from_now) { post url, params: { name: "Late", body: "Too late" } }

      expect(response).to have_http_status(:not_found)
      expect(Accounting::Comment.where(external_name: "Late")).to be_empty
    end

    it "is refused once the link was revoked" do
      url = external_reply_path(token: token)
      Accounting::RevokeExternalLink.call(task: task, user: accountant)

      post url, params: { name: "Late", body: "Hello" }

      expect(response).to have_http_status(:not_found)
    end

    it "changes nothing in what the task is about" do
      before = partner.reload.attributes

      reply

      expect(partner.reload.attributes).to eq(before)
    end
  end

  describe "the throttle" do
    around do |example|
      Rack::Attack.enabled = true
      Rack::Attack.cache.store.clear
      example.run
    ensure
      Rack::Attack.enabled = false
    end

    it "limits the tries on this public page per address" do
      21.times { get external_reply_path(token: "guess-#{SecureRandom.hex(4)}") }

      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
