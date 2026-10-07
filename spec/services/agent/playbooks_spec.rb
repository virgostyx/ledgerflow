require "rails_helper"

# A08: the protocols are text the application owns; their structure, their tools and their links are checked like code. `validated` says whether an accountant read the content.
RSpec.describe Agent::Playbooks do
  let(:tools) { Agent::ToolRegistry.default.definitions.map { |definition| definition[:name] } }
  let(:check_ids) { Accounting::Consistency::Check.registry.map { |check| check.check_id } }

  it "has a protocol for every consistency check, for the invariants they replay, for the aged balance gap and for a variation" do
    expect(described_class.ids).to include(*check_ids, "I2", "I5", "I6", "I7", "I11", "R04", "variation")
  end

  it "gives every protocol the same parts, filled in" do
    described_class.all.each do |playbook|
      expect(playbook.symptom).to be_present, playbook.id
      expect(playbook.causes).not_to be_empty, playbook.id
      expect(playbook.checks).not_to be_empty, playbook.id
      expect(playbook.interpretation).to be_present, playbook.id
      expect(playbook.fix_steps).not_to be_empty, playbook.id
      expect(playbook.prevention).to be_present, playbook.id
      expect(playbook.escalate).to be_present, playbook.id
    end
  end

  it "names only tools the agent has, and only screens the application has" do
    described_class.all.each do |playbook|
      expect(playbook.checks.map { |check| check[:tool] }).to all(satisfy { |tool| tools.include?(tool) }), "#{playbook.id} names a tool that does not exist"
      expect(playbook.fix_steps.filter_map { |step| step[:screen] }).to all(satisfy { |screen| Agent::Screens.path(screen) }), "#{playbook.id} points to a screen that does not exist"
    end
  end

  it "sends every step of a fix to a screen of the application" do
    described_class.all.each { |playbook| expect(playbook.fix_steps.map { |step| step[:screen] }).to all(be_present), "#{playbook.id} has a step with no screen" }
  end

  it "says that no accountant validated a protocol until one did" do
    expect(described_class.all.map(&:validated)).to all(be(false))
  end

  it "finds the protocol of a finding: the invariant for an invariant anomaly, the check otherwise, none for an unknown check" do
    expect(described_class.for_finding("C04").id).to eq("C04")
    expect(described_class.for_finding("C11", { "invariant" => "I7" }).id).to eq("I7")
    expect(described_class.for_finding("C11", {}).id).to eq("C11")
    expect(described_class.for_finding("C99")).to be_nil
  end

  it "does not read a file out of its directory" do
    expect(described_class.find("../../../config/database")).to be_nil
  end

  it "gives a tool result a protocol whose steps point to references, not addresses" do
    hash = described_class.find("C04").to_h_for_tool

    expect(hash["fix_steps"].first).to include("ref" => "screen:lettering")
    expect(hash.to_json).not_to include("/accounting/")
  end
end
