require "rails_helper"

# F09 step 5: nothing leaves before the validation; each sending updates the lines and the history of the customer and leaves a follow-up task.
RSpec.describe Accounting::SendDunningRun do
  include ActiveJob::TestHelper
  include_context "with open customer lines"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: ActsAsTenant.current_tenant) } }
  let!(:line) { open_line(amount: 100, days_overdue: 30) }
  let(:run) { Accounting::PrepareDunningRun.call(user: user, on: as_of)[:run] }
  let(:item) { run.items.sole }

  before { ActionMailer::Base.deliveries.clear }

  def send_run(**)
    result = nil
    perform_enqueued_jobs { result = described_class.call(run: run, user: user, **) }
    result
  end
  def mail = ActionMailer::Base.deliveries.sole

  it "sends nothing until it is called" do
    run
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(item).to be_pending
  end

  describe "an e-mail" do
    it "goes to the recipient with the text of the item and the statement of account attached" do
      item.update!(body: "Please pay up")
      send_run

      expect(mail.to).to eq([ "alice@example.com" ])
      expect(mail.subject).to eq(item.subject)
      expect(mail.text_part&.body&.to_s || mail.body.to_s).to include("Please pay up")
      expect(mail.attachments.map(&:filename)).to include("statement-of-account.pdf")
    end

    it "carries the original invoices of F03 linked to the entries it asks for" do
      document = create(:document, name: "inv-2026-001.pdf", kind: :sales_invoice, status: :linked)
      Accounting::DocumentLink.create!(document: document, target: line.journal_entry)
      send_run

      expect(mail.attachments.map(&:filename)).to include("inv-2026-001.pdf")
    end

    it "takes the sender and the reply address from the policy" do
      policy.update!(from_name: "Acme Collections", reply_to: "compta@acme.example")
      send_run
      expect(mail[:from].to_s).to include("Acme Collections")
      expect(mail.reply_to).to eq([ "compta@acme.example" ])
    end

    it "marks the item and the run as sent, with the time and the message id" do
      send_run
      expect(item.reload).to have_attributes(status: "sent", message_id: mail.message_id)
      expect(item.sent_at).to be_within(1.minute).of(Time.current)
      expect(run.reload).to be_sent
    end
  end

  describe "after the sending (criterion 5)" do
    it "records the level and the date on the lines asked for, and only on those" do
      other = open_line(amount: 40, days_overdue: 30, disputed: true)
      send_run

      expect(line.reload).to have_attributes(dunning_level: 1)
      expect(line.last_dunned_at).to be_within(1.minute).of(Time.current)
      expect(other.reload).to have_attributes(dunning_level: 0, last_dunned_at: nil)
    end

    it "lets the next run propose the next level only, once the minimum days between two reminders have passed" do
      send_run
      expect(Accounting::DunningCandidates.new(as_of: as_of + 13).call).to be_empty
      expect(Accounting::DunningCandidates.new(as_of: as_of + 14).call.sole).to have_attributes(level: 2)
    end

    it "leaves a follow-up task on the customer, due in 7 days by default, for the person who sent" do
      send_run
      task = Accounting::Task.sole
      expect(task).to have_attributes(target: alice, assignee: user, due_on: as_of + 7, kind: "client_question")
      expect(task.title).to include("Alice", "1")
    end

    it "takes the delay of the follow-up from the policy" do
      policy.update!(follow_up_days: 3)
      send_run
      expect(Accounting::Task.sole.due_on).to eq(as_of + 3)
    end

    it "is in the audit trail" do
      send_run
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::DunningItem", auditable_id: item.id)).to exist
    end
  end

  describe "what is not sent" do
    it "leaves out an item that was excluded" do
      item.update!(excluded: true)
      send_run
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Accounting::Task.count).to eq(0)
      expect(line.reload.dunning_level).to eq(0)
    end

    it "does not send a level that skips one without its confirmation (criterion 2), and sends it once confirmed" do
      Accounting::UpdateDunningItem.call(item: item, level: 3)
      result = send_run
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(result[:blocked].map { |b| b[:item] }).to eq([ item ])
      expect(item.reload).to be_pending

      Accounting::UpdateDunningItem.call(item: item, level: 3, skip_confirmed: true)
      send_run
      expect(item.reload).to be_sent
      expect(line.reload.dunning_level).to eq(3)
    end

    it "does not send to a customer that has been marked 'do not remind' since the preparation" do
      item
      alice.update!(do_not_dun: true)
      result = send_run
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(result[:blocked].sole[:reason]).to match(/do not remind/i)
    end

    it "does not send what changed since the preparation (a dispute or a promise entered meanwhile)" do
      item
      line.update_columns(disputed: true)
      result = send_run
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(result[:blocked].sole[:reason]).to match(/changed since/i)
    end

    it "sends an item only once" do
      item
      send_run
      expect { send_run }.not_to(change { ActionMailer::Base.deliveries.size })
    end
  end

  describe "a letter" do
    before { alice.update!(email: nil) }

    it "is sent without an e-mail: validating it means it is printed, and its PDF is kept on the item" do
      send_run
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(item.reload).to have_attributes(status: "sent", channel: "letter")
      expect(item.letter_pdf).to be_attached
      expect(line.reload.dunning_level).to eq(1)
      expect(Accounting::Task.count).to eq(1)
    end
  end

  describe "a bounce (criterion 6)" do
    before do
      allow(Accounting::DunningMailer).to receive(:reminder).and_wrap_original do |original, *args|
        original.call(*args).tap { |m| allow(m).to receive(:deliver_now).and_raise(Net::SMTPFatalError.new("550 5.1.1 user unknown")) }
      end
    end

    it "is kept on the item, flags the customer, and counts as no reminder: no level, no task" do
      send_run
      expect(item.reload).to have_attributes(status: "bounced")
      expect(item.error).to include("550")
      expect(alice.reload.email_bounced_at).to be_within(1.minute).of(Time.current)
      expect(line.reload.dunning_level).to eq(0)
      expect(Accounting::Task.count).to eq(0)
      expect(Accounting::AuditLog.where(auditable_type: "Accounting::DunningItem", auditable_id: item.id).pluck(:action)).to include("update")
    end

    it "lets the customer be proposed again, flagged" do
      send_run
      expect(Accounting::DunningCandidates.new(as_of: as_of).call.sole.partner.email_bounced_at).to be_present
    end
  end

  it "keeps the item to send again after a technical error, with the reason" do
    allow(Accounting::DunningMailer).to receive(:reminder).and_wrap_original do |original, *args|
      original.call(*args).tap { |m| allow(m).to receive(:deliver_now).and_raise(Timeout::Error, "smtp timeout") }
    end
    send_run
    expect(item.reload).to be_pending
    expect(item.error).to include("smtp timeout")
    expect(alice.reload.email_bounced_at).to be_nil
  end
end
