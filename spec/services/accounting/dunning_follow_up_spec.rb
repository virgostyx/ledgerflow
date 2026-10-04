require "rails_helper"

# F09 step 6: a dispute and a promise of payment keep a line out of the reminders; a promise that is past brings it back, with a task.
RSpec.describe "Dunning: disputes and promises" do
  include ActiveJob::TestHelper
  include_context "with open customer lines"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: ActsAsTenant.current_tenant) } }
  let!(:line) { open_line(amount: 100, days_overdue: 30) }

  def proposed = Accounting::DunningCandidates.new(as_of: as_of).call

  describe "a prepared reminder when one of its lines is disputed or promised" do
    let!(:other) { open_line(amount: 40, days_overdue: 25) }
    let(:item) { Accounting::PrepareDunningRun.call(user: user, on: as_of)[:run].items.sole }

    it "drops the line, with its amount, from the reminder and from its text, and the reminder can still go" do
      item
      Accounting::SetLineDispute.call(line: other, disputed: true, user: user)
      item.reload

      expect(item.item_lines.map(&:line_id)).to eq([ line.id ])
      expect(item.total).to eq(BigDecimal("100"))
      expect(item.body).to include("100,00").and not_include("140,00")
      expect(item).not_to be_excluded
    end

    it "does the same for a promise, and recomputes the charges" do
      policy.update!(interest_enabled: true, interest_rate: 10)
      item
      expect(item.interest).to be > 0
      before = item.interest
      Accounting::SetPaymentPromise.call(line: other, on: as_of + 3, user: user)
      expect(item.reload.interest).to be < before
    end

    it "keeps the text a person wrote" do
      item.update!(body: "My own words")
      Accounting::SetLineDispute.call(line: other, disputed: true, user: user)
      expect(item.reload.body).to eq("My own words")
      expect(item.total).to eq(BigDecimal("100"))
    end

    it "leaves the customer out when no line is left" do
      item
      Accounting::SetLineDispute.call(line: line, disputed: true, user: user)
      Accounting::SetLineDispute.call(line: other, disputed: true, user: user)
      expect(item.reload).to be_excluded
    end

    it "leaves a reminder that was already sent as it was" do
      item
      perform_enqueued_jobs { Accounting::SendDunningRun.call(run: item.run, user: user) }
      Accounting::SetLineDispute.call(line: other, disputed: true, user: user)
      expect(item.reload.item_lines.size).to eq(2)
    end
  end

  describe Accounting::SetLineDispute do
    it "keeps the line out of the reminders, and puts it back when the dispute is over" do
      expect(described_class.call(line: line, disputed: true, user: user)).to be_success
      expect(line.reload).to be_disputed
      expect(proposed).to be_empty

      described_class.call(line: line, disputed: false, user: user)
      expect(proposed.sole.total).to eq(BigDecimal("100"))
    end

    it "is in the audit trail, with who did it" do
      described_class.call(line: line, disputed: true, user: user)
      log = Accounting::AuditLog.where(auditable_type: "Accounting::JournalEntryLine", auditable_id: line.id, action: "dunning_dispute").sole
      expect(log.user_id).to eq(user.id)
      expect(log.payload).to include("disputed" => true)
    end

    it "is refused for a line that is not a customer's" do
      supplier_line = open_line.tap { |l| l.update_columns(account_id: create(:account, :supplier, reconcilable: true).id) }
      expect(described_class.call(line: supplier_line, disputed: true, user: user)).to be_failure
    end

    it "works on a line of a locked period: it changes no amount" do
      create(:period_lock, starts_on: line.journal_entry.entry_date.beginning_of_month, ends_on: line.journal_entry.entry_date.end_of_month)
      expect(described_class.call(line: line, disputed: true, user: user)).to be_success
      expect(line.reload).to be_disputed
    end
  end

  describe Accounting::SetPaymentPromise do
    it "keeps the line out of the reminders until the day after the promised date" do
      expect(described_class.call(line: line, on: as_of + 5, user: user)).to be_success
      expect(proposed).to be_empty
      expect(Accounting::DunningCandidates.new(as_of: as_of + 5).call).to be_empty
      expect(Accounting::DunningCandidates.new(as_of: as_of + 6).call.sole.total).to eq(BigDecimal("100"))
    end

    it "is cleared with no date" do
      described_class.call(line: line, on: as_of + 5, user: user)
      described_class.call(line: line, on: nil, user: user)
      expect(line.reload.payment_promised_on).to be_nil
    end

    it "refuses a date in the past" do
      expect(described_class.call(line: line, on: as_of - 1, user: user)).to be_failure
    end

    it "is in the audit trail" do
      described_class.call(line: line, on: as_of + 5, user: user)
      expect(Accounting::AuditLog.where(auditable_id: line.id, action: "dunning_promise").sole.payload).to include("payment_promised_on" => (as_of + 5).iso8601)
    end
  end

  describe Accounting::DunningPromisesJob do
    before { line.update_columns(payment_promised_on: as_of - 1) }

    it "brings back a line whose promise is past, with a task on the customer for the person who took the promise" do
      Accounting::AuditLog.record!(auditable: line, action: "dunning_promise", user: user, payload: { payment_promised_on: (as_of - 1).iso8601 })
      expect { described_class.perform_now }.to change(Accounting::Task, :count).by(1)

      task = Accounting::Task.sole
      expect(task).to have_attributes(target: alice, kind: "client_question", due_on: as_of, assignee: user)
      expect(task.title).to include("Alice", "not kept")
      expect(line.reload.payment_promised_on).to be_nil
      expect(proposed.sole.total).to eq(BigDecimal("100"))
    end

    it "makes one task however many times it runs" do
      described_class.perform_now
      expect { described_class.perform_now }.not_to change(Accounting::Task, :count)
    end

    it "makes no task when the line has been paid meanwhile" do
      credit = open_line(side: :credit, amount: 100, days_overdue: 1)
      lettering = create(:lettering, account: customer_account, partner: alice)
      Accounting::JournalEntryLine.where(id: [ line.id, credit.id ]).update_all(lettering_id: lettering.id)
      expect { described_class.perform_now }.not_to change(Accounting::Task, :count)
      expect(line.reload.payment_promised_on).to be_nil
    end

    it "leaves a promise that is not past" do
      line.update_columns(payment_promised_on: as_of)
      expect { described_class.perform_now }.not_to change(Accounting::Task, :count)
      expect(line.reload.payment_promised_on).to eq(as_of)
    end
  end
end

RSpec.describe Accounting::RecordDunningBounce do
  include ActiveJob::TestHelper
  include_context "with open customer lines"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: ActsAsTenant.current_tenant) } }
  let!(:line) { open_line(amount: 100, days_overdue: 30) }

  def send_item(on:)
    run = Accounting::PrepareDunningRun.call(user: user, on: on)[:run]
    perform_enqueued_jobs { Accounting::SendDunningRun.call(run: run, user: user) }
    run.items.sole
  end

  it "flags the customer, keeps the reason, and takes the lines back to what they were" do
    item = send_item(on: as_of)
    expect(line.reload.dunning_level).to eq(1)

    expect(described_class.call(item: item, reason: "Mailbox full")).to be_success
    expect(item.reload).to have_attributes(status: "bounced", error: "Mailbox full")
    expect(alice.reload.email_bounced_at).to be_present
    expect(line.reload).to have_attributes(dunning_level: 0, last_dunned_at: nil)
  end

  it "takes the lines back to the earlier reminder, not to nothing, when there was one" do
    first = send_item(on: as_of - 20)
    first.update_columns(sent_at: 20.days.ago)
    line.update_columns(last_dunned_at: 20.days.ago)
    second = send_item(on: as_of)
    expect(line.reload.dunning_level).to eq(2)

    described_class.call(item: second, reason: "x")
    expect(line.reload).to have_attributes(dunning_level: 1)
    expect(line.last_dunned_at).to be_within(1.second).of(first.sent_at)
  end

  it "is refused for a reminder that did not go out by e-mail" do
    run = Accounting::PrepareDunningRun.call(user: user, on: as_of)[:run]
    expect(described_class.call(item: run.items.sole, reason: "x")).to be_failure
  end
end
