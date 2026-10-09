require "rails_helper"

RSpec.describe Approvals::ProcessDueJob do
  it "runs the timers of the approvals" do
    allow(Approvals::ProcessDue).to receive(:call)

    described_class.perform_now

    expect(Approvals::ProcessDue).to have_received(:call)
  end

  it "is scheduled every hour in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "approvals_process_due")

    expect(schedule).to include("class" => "Approvals::ProcessDueJob", "schedule" => "every hour")
  end
end
