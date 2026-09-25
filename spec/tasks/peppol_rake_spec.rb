require "rails_helper"
require "rake"

RSpec.describe "peppol:simulator:deliver" do
  include_context "with_open_fiscal_year"

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("peppol:simulator:deliver")
    Rake::Task["peppol:simulator:deliver"].reenable
  end

  it "delivers a queued message" do
    invoice = create(:invoice, :posted, partner: create(:partner, :with_vat), fiscal_year: fiscal_year,
                     peppol_id: "SIM-1", peppol_status: :queued)
    expect { Rake::Task["peppol:simulator:deliver"].invoke("SIM-1") }.to output("Delivered\n").to_stdout
    expect(invoice.reload.peppol_status).to eq("delivered")
  end

  it "aborts on an unknown message" do
    expect { Rake::Task["peppol:simulator:deliver"].invoke("NOPE") }.to raise_error(SystemExit).and output(/No invoice/).to_stderr
  end
end

RSpec.describe "peppol:simulator:receive" do
  include_context "with_open_fiscal_year"

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("peppol:simulator:receive")
    Rake::Task["peppol:simulator:receive"].reenable
  end

  it "books an incoming invoice for a simulator entity" do
    entity.update!(peppol_access_point: :simulator, peppol_participant_id: "0208:0123456789")
    expect { Rake::Task["peppol:simulator:receive"].invoke(entity.id.to_s) }.to output(/Booked draft invoice SIM-/).to_stdout
  end

  it "aborts for an entity that is not on the simulator" do
    expect { Rake::Task["peppol:simulator:receive"].invoke(entity.id.to_s) }.to raise_error(SystemExit).and output(/not on the simulator/).to_stderr
  end
end
