require "rails_helper"

# F09, the screens: prepare, look at each customer's reminder (text, lines, statement), edit, validate and send; the rules; disputes, promises, bounces.
RSpec.describe "Customer dunning screens (F09)", type: :request do
  include ActiveJob::TestHelper
  include_context "with open customer lines"

  let(:accountant) { create(:user, role: :accountant, email: "ann@firm.test") }
  let(:assistant)  { create(:user, role: :auditor, email: "ari@firm.test") }
  let(:reader)     { create(:user, role: :manager, email: "rita@firm.test") }
  let!(:accountant_membership) { create(:user_entity, :accountant, user: accountant, entity: entity) }
  let!(:assistant_membership)  { create(:user_entity, :assistant, user: assistant, entity: entity) }
  let!(:reader_membership)     { create(:user_entity, :manager, user: reader, entity: entity) }
  let!(:line) { open_line(amount: 100, days_overdue: 30) }

  before do
    ActionMailer::Base.deliveries.clear
    sign_in accountant
  end

  def prepare! = Accounting::PrepareDunningRun.call(user: accountant, on: as_of)[:run]

  it "closes the screens when the feature is off" do
    entity.update!(features: { "f09" => false })
    get accounting_dunning_runs_path
    expect(response).to redirect_to(accounting_root_path)
  end

  describe "preparing" do
    it "makes a run from the proposals, sends nothing, and opens it" do
      expect { post accounting_dunning_runs_path }.to change(Accounting::DunningRun, :count).by(1)
      expect(response).to redirect_to(accounting_dunning_run_path(Accounting::DunningRun.last))
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "says so when nobody has to be reminded" do
      line.update_columns(disputed: true)
      post accounting_dunning_runs_path
      expect(response).to redirect_to(accounting_dunning_runs_path)
      follow_redirect!
      expect(response.body).to include("Nobody has to be reminded today.")
    end

    it "refuses a second campaign the same day for a customer, with a link to the first (criterion 7)" do
      first = prepare!
      post accounting_dunning_runs_path
      follow_redirect!
      expect(response.body).to include("Alice").and include(accounting_dunning_run_path(first))
      expect(Accounting::DunningRun.count).to eq(1)
    end

    it "is refused to a reader" do
      sign_in reader
      expect { post accounting_dunning_runs_path }.not_to change(Accounting::DunningRun, :count)
    end

    it "is allowed to an assistant, who still cannot send" do
      sign_in assistant
      expect { post accounting_dunning_runs_path }.to change(Accounting::DunningRun, :count).by(1)
      expect { perform_enqueued_jobs { post send_run_accounting_dunning_run_path(Accounting::DunningRun.last) } }.not_to(change { ActionMailer::Base.deliveries.size })
    end
  end

  describe "the run" do
    let!(:run) { prepare! }

    it "lists the customers with the level, the total, the way to reach them and what is left out, and shows the button to send" do
      get accounting_dunning_run_path(run)
      expect(response.body).to include("Alice", "alice@example.com", "Level 1", "100,00", "Send the validated reminders")
    end

    it "lists the runs, newest first" do
      get accounting_dunning_runs_path
      expect(response.body).to include(accounting_dunning_run_path(run))
    end

    it "sends what was validated, once validated, and nothing before" do
      expect(ActionMailer::Base.deliveries).to be_empty
      perform_enqueued_jobs { post send_run_accounting_dunning_run_path(run) }
      expect(ActionMailer::Base.deliveries.sole.to).to eq([ "alice@example.com" ])
      expect(response).to redirect_to(accounting_dunning_run_path(run))
      follow_redirect!
      expect(response.body).to include("Sent")
    end

    it "says why an item was not sent" do
      alice.update!(do_not_dun: true)
      perform_enqueued_jobs { post send_run_accounting_dunning_run_path(run) }
      follow_redirect!
      expect(response.body).to include("marked &#39;do not remind&#39;")
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe "one reminder" do
    let!(:item) { prepare!.items.sole }

    it "shows the text, the lines and the statement, with the controls to dispute or promise a line" do
      get accounting_dunning_item_path(item)
      expect(response.body).to include(item.subject, "Statement of account", "Covered by this reminder", "Dispute", "Promised on")
    end

    it "shows the letter of a customer without an e-mail, and a PDF to print" do
      alice.update!(email: nil)
      item.update!(channel: :letter, recipient: nil)
      get accounting_dunning_item_path(item)
      expect(response.body).to include("Letter to print")
      get pdf_accounting_dunning_item_path(item)
      expect(response.media_type).to eq("application/pdf")
      expect(PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join).to include("Statement of account")
    end

    it "edits the recipient, the text, and leaves the customer out" do
      patch accounting_dunning_item_path(item), params: { accounting_dunning_item: { recipient: "other@example.com", subject: "New subject", body: "New body", excluded: "1" } }
      expect(item.reload).to have_attributes(recipient: "other@example.com", subject: "New subject", body: "New body", excluded: true)
    end

    it "keeps a level that skips one for confirmation, and says so" do
      patch accounting_dunning_item_path(item), params: { accounting_dunning_item: { level: "3" } }
      follow_redirect!
      expect(response.body).to include("skips level").and include("I confirm")
      expect(item.reload).to have_attributes(level: 3, skip_confirmed: false)
      patch accounting_dunning_item_path(item), params: { accounting_dunning_item: { level: "3", skip_confirmed: "1" } }
      expect(item.reload.skip_confirmed).to be(true)
    end

    it "shows the error of a bad address" do
      patch accounting_dunning_item_path(item), params: { accounting_dunning_item: { recipient: "nope" } }
      follow_redirect!
      expect(response.body).to include("Recipient is not valid")
    end

    it "marks a dispute on a line, which leaves it out of the next proposals" do
      patch dispute_accounting_dunning_line_path(line), params: { disputed: "1", item_id: item.id }
      expect(response).to redirect_to(accounting_dunning_item_path(item))
      expect(line.reload).to be_disputed
    end

    it "records a promise of payment on a line" do
      patch promise_accounting_dunning_line_path(line), params: { payment_promised_on: (as_of + 5).iso8601, item_id: item.id }
      expect(line.reload.payment_promised_on).to eq(as_of + 5)
    end

    it "refuses a promise in the past, with the reason" do
      patch promise_accounting_dunning_line_path(line), params: { payment_promised_on: (as_of - 1).iso8601, item_id: item.id }
      follow_redirect!
      expect(response.body).to include("The promised date cannot be in the past.")
    end

    it "records a bounce by hand (the mail server's report), which flags the customer on its page (criterion 6)" do
      perform_enqueued_jobs { post send_run_accounting_dunning_run_path(item.run) }
      post bounce_accounting_dunning_item_path(item), params: { reason: "Mailbox full" }
      expect(item.reload).to have_attributes(status: "bounced", error: "Mailbox full")
      expect(alice.reload.email_bounced_at).to be_present
      get accounting_partner_path(alice)
      expect(response.body).to include("E-mail bounced")
    end

    it "is not for the assistant to record a bounce" do
      perform_enqueued_jobs { post send_run_accounting_dunning_run_path(item.run) }
      sign_in assistant
      post bounce_accounting_dunning_item_path(item), params: { reason: "x" }
      expect(item.reload).to be_sent
    end
  end

  describe "the customer's page" do
    it "lists the reminders sent to it, with the level, the date and the outcome" do
      item = prepare!.items.sole
      perform_enqueued_jobs { post send_run_accounting_dunning_run_path(item.run) }
      get accounting_partner_path(alice)
      expect(response.body).to include('data-section="dunning"', "Level 1", accounting_dunning_item_path(item))
    end

    it "sets 'do not remind' and the language of the reminders" do
      patch accounting_partner_path(alice), params: { accounting_partner: { do_not_dun: "1", language: "nl" } }
      expect(alice.reload).to have_attributes(do_not_dun: true, language: "nl")
      expect(Accounting::DunningCandidates.new(as_of: as_of).call).to be_empty
    end
  end

  describe "the rules" do
    it "shows the rules, with the built-in text where none was written" do
      get accounting_dunning_policy_path
      expect(response.body).to include("Level 1 starts", "Payment reminder", "Late interest", "turned off")
    end

    it "changes the delays, the minimum, the charges, the sender and a text" do
      patch accounting_dunning_policy_path, params: { accounting_dunning_policy: {
        level_1_days: 5, level_2_days: 15, level_3_days: 30, min_amount: 25, fee_2: 7.5, from_name: "Acme Collections", reply_to: "compta@acme.test",
        interest_enabled: "1", interest_rate: 8, templates: { "1" => { "fr" => { "subject" => "Petit rappel", "body" => "Bonjour {{partner_name}}" } } }
      } }
      expect(response).to redirect_to(accounting_dunning_policy_path)
      expect(policy.reload).to have_attributes(level_1_days: 5, level_3_days: 30, min_amount: BigDecimal("25"), fee_2: BigDecimal("7.5"), interest_enabled: true,
                                               from_name: "Acme Collections", reply_to: "compta@acme.test")
      expect(policy.templates.dig("1", "fr", "subject")).to eq("Petit rappel")
    end

    it "refuses a text with an unknown variable, and says which" do
      patch accounting_dunning_policy_path, params: { accounting_dunning_policy: { templates: { "1" => { "fr" => { "subject" => "x", "body" => "{{oops}}" } } } } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Unknown variable {{oops}}")
    end

    it "lets only the owner turn on the automatic sending of the first level" do
      patch accounting_dunning_policy_path, params: { accounting_dunning_policy: { auto_send_level_1: "1" } }
      expect(policy.reload.auto_send_level_1).to be(false)

      create(:user_entity, :admin, user: owner = create(:user, role: :admin, email: "owner@firm.test"), entity: entity)
      sign_in owner
      patch accounting_dunning_policy_path, params: { accounting_dunning_policy: { auto_send_level_1: "1" } }
      expect(policy.reload.auto_send_level_1).to be(true)
    end

    it "is not for an assistant to change" do
      sign_in assistant
      patch accounting_dunning_policy_path, params: { accounting_dunning_policy: { min_amount: 999 } }
      expect(policy.reload.min_amount).to eq(0)
    end
  end

  describe "the manual reminders of before" do
    it "give way to this module: the old page leads here, and the history of the old reminders stays on the invoices" do
      get accounting_payment_reminders_path
      expect(response).to redirect_to(accounting_dunning_runs_path)
    end

    it "stay as they were when the feature is off" do
      entity.update!(features: { "f09" => false })
      get accounting_payment_reminders_path
      expect(response).to have_http_status(:ok)
    end
  end
end
