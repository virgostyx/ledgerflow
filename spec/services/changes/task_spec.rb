require "rails_helper"

# B03b "Revue et suivi": from any change, "Create a task" (F08) about what changed, visible only to who may see it.
RSpec.describe Changes::Task do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let(:journal) { create(:journal, :misc, code: "OD") }
  let!(:account) { create(:account, code: "604000", label_fr: "Services", account_type: :expense, normal_balance: :debit, account_class: 6) }

  it "makes a task about the entry of an 'entry:<id>' change" do
    entry = create(:journal_entry, :posted, fiscal_year: fiscal_year, journal: journal, reference: "T-1")

    result = described_class.call(key: "entry:#{entry.id}", user: user)

    expect(result).to be_success
    expect(result[:task]).to have_attributes(target: entry, kind: "to_check", author: user)
    expect(result[:task].title).to include("T-1")
  end

  it "makes a task about the object of another change, when it is something a task can be about" do
    key = Changes::Key.for(Changes::Events::Event.new(category: :setup, at: Time.current, action: "master_data_version", subject_type: "Accounting::Account", subject_id: account.id))

    result = described_class.call(key: key, user: user)

    expect(result[:task].target).to eq(account)
  end

  it "makes a task about nothing, naming the change, when the object cannot be a target" do
    key = Changes::Key.for(Changes::Events::Event.new(category: :locks, at: Time.current, action: "lock_period", subject_type: "Accounting::FiscalYear", subject_id: fiscal_year.id))

    result = described_class.call(key: key, user: user)

    expect(result).to be_success
    expect(result[:task].target).to be_nil
    expect(result[:task].description).to include("lock_period")
  end

  it "refuses a key that is not one, and an entry of another company" do
    expect(described_class.call(key: "nonsense", user: user)).to be_failure
    other = create(:entity)
    foreign = ActsAsTenant.with_tenant(other) { create(:journal_entry, :posted, entity: other, fiscal_year: create(:fiscal_year, entity: other), journal: create(:journal, entity: other), reference: "X-1") }

    expect(described_class.call(key: "entry:#{foreign.id}", user: user)).to be_failure
  end

  it "is refused to who may not manage tasks" do
    reader = create(:user).tap { |u| create(:user_entity, :manager, user: u, entity: entity) }
    entry = create(:journal_entry, :posted, fiscal_year: fiscal_year, journal: journal, reference: "T-2")

    expect(described_class.call(key: "entry:#{entry.id}", user: reader)).to be_failure
  end
end
