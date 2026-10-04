require "rails_helper"

# F09, criterion 3: with `auto_send_level_1` on, the first level goes by itself and nothing else does.
RSpec.describe Accounting::DunningAutoSendJob do
  include ActiveJob::TestHelper
  include_context "with open customer lines"

  before { ActionMailer::Base.deliveries.clear }

  def run_job = perform_enqueued_jobs { described_class.perform_now }

  it "sends nothing by default, and prepares nothing" do
    open_line
    run_job
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(Accounting::DunningRun.count).to eq(0)
  end

  context "with the option on" do
    before { policy.update!(auto_send_level_1: true) }

    it "sends the first level by e-mail, in a run marked automatic, with the follow-up task and the history" do
      line = open_line(amount: 100, days_overdue: 30)
      run_job

      expect(ActionMailer::Base.deliveries.sole.to).to eq([ "alice@example.com" ])
      expect(Accounting::DunningRun.sole).to have_attributes(auto: true, created_by: nil, status: "sent")
      expect(Accounting::DunningItem.sole).to be_sent
      expect(line.reload.dunning_level).to eq(1)
      expect(Accounting::Task.sole).to have_attributes(target: alice, assignee: nil)
    end

    it "does not send the second or third level" do
      open_line(days_overdue: 40, dunning_level: 1, last_dunned_at: 20.days.ago)
      run_job
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(Accounting::DunningItem.count).to eq(0)
    end

    it "does not send a letter by itself: printing is a human act" do
      open_line(partner: bob)
      run_job
      expect(Accounting::DunningItem.count).to eq(0)
    end

    it "sends the first level of a customer and leaves the others to a person" do
      open_line(partner: alice, days_overdue: 30)
      open_line(partner: create(:partner, name: "Carl", email: "carl@example.com", payment_terms_days: 0), days_overdue: 40, dunning_level: 1, last_dunned_at: 20.days.ago)
      run_job
      expect(Accounting::DunningItem.all.map(&:partner)).to eq([ alice ])
      run = Accounting::PrepareDunningRun.call(user: nil, on: as_of)
      expect(run[:run].items.map(&:partner).map(&:name)).to eq([ "Carl" ]) # a person still prepares it; Alice is refused today (criterion 7)
    end

    it "does nothing for an entity that has not turned the feature on" do
      ActsAsTenant.current_tenant.update!(features: { "f09" => false })
      open_line
      run_job
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
