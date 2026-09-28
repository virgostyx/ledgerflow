require "rails_helper"

RSpec.describe Accounting::Consistency::Runner, type: :service do
  include_context "with_open_fiscal_year"

  let(:journal)  { create(:journal, :purchase) }
  let!(:bank)    { create(:account, code: "550000", label_fr: "Bank", account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:sales)   { create(:account, code: "700000", label_fr: "Sales", account_class: 7, account_type: :revenue, normal_balance: :credit) }
  let(:admin)    { create(:user, role: :admin) }
  let!(:admin_membership) { create(:user_entity, :admin, user: admin, entity: entity) }

  # An unbalanced entry: a blocking C01 anomaly.
  let!(:bad_entry) do
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 3)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: bank, debit: 100, credit: 0)
    create(:journal_entry_line, journal_entry: entry, account: sales, debit: 0, credit: 90)
    entry
  end

  it "stores the run with its findings and counts per severity" do
    run = described_class.call(trigger: "manual")
    expect(run).to have_attributes(trigger: "manual", finished_at: be_present)
    expect(run.counts["blocking"]).to be >= 1
    expect(run.findings.where(check_id: "C01").count).to eq(1)
    expect(run.duration_ms).to be >= 0
  end

  it "hides an acknowledged anomaly, and brings it back when its data changes" do
    first = described_class.call
    finding = first.findings.find_by(check_id: "C01")
    Accounting::ConsistencyAcknowledgement.create!(fingerprint: finding.fingerprint, comment: "Known, fixing Monday", acknowledged_at: Time.current)

    second = described_class.call
    expect(second.counts["blocking"]).to eq(first.counts["blocking"] - 1)
    expect(second.counts["acknowledged"]).to eq(1)

    create(:journal_entry_line, journal_entry: bad_entry, account: bank, debit: 5, credit: 0) # amounts change: same entry, new anomaly
    third = described_class.call
    expect(third.findings.find_by(check_id: "C01").fingerprint).not_to eq(finding.fingerprint)
    expect(third.counts["acknowledged"]).to eq(0)
  end

  it "keeps the other checks running when one raises, and records the error" do
    boom = Class.new(Accounting::Consistency::Check) { self.check_id = "C99"; self.severity = "info"; def call = raise("boom") }
    allow(Accounting::Consistency::Check).to receive(:registry).and_wrap_original { |m| m.call + [ boom ] }
    run = described_class.call
    expect(run.errors_by_check).to include("C99" => a_string_including("boom"))
    expect(run.findings.where(check_id: "C01")).to exist
  end

  it "adds a check by adding one class: the runner only reads the registry" do
    extra = Class.new(Accounting::Consistency::Check) do
      self.check_id = "C98"
      self.severity = "info"
      def call = [ finding(subject: [ "Accounting::Account", 1 ], message: "extra") ]
    end
    allow(Accounting::Consistency::Check).to receive(:registry).and_wrap_original { |m| m.call + [ extra ] }
    expect(described_class.call.findings.where(check_id: "C98").count).to eq(1)
  end

  it "discovers every check file in the directory" do
    files = Dir[File.join(Accounting::Consistency::Check::CHECKS_DIR, "*.rb")].map { |f| File.basename(f, ".rb") }
    expect(Accounting::Consistency::Check.registry.map { |c| c.name.demodulize.underscore }).to match_array(files)
  end

  describe "notification" do
    include ActiveJob::TestHelper

    it "mails the entity administrators about a new blocking anomaly, once" do
      expect { described_class.call }.to have_enqueued_mail(Accounting::ConsistencyMailer, :blocking_findings).with(admin, anything, be >= 1)
      expect { described_class.call }.not_to have_enqueued_mail(Accounting::ConsistencyMailer, :blocking_findings)
    end
  end

  describe Accounting::ConsistencyCheckJob do
    it "runs one nightly run per entity inside its tenant" do
      expect { described_class.perform_now }.to change { ActsAsTenant.without_tenant { Accounting::ConsistencyRun.count } }.by(Entity.count)
      expect(ActsAsTenant.without_tenant { Accounting::ConsistencyRun.last.trigger }).to eq("nightly")
    end
  end
end
