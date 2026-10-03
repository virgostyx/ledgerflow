require "rails_helper"

# F01: what a person may do comes from the system role of the access, or from its custom role when it has one.
RSpec.describe "Rights given by a custom role" do
  include_context "with_open_fiscal_year"

  let(:user) { create(:user) }
  let(:custom) { CustomRole.create!(name: "Poster", permissions: %w[records.view records.list entries.post reports.view]) }
  let!(:membership) { create(:user_entity, :manager, user: user, entity: entity, custom_role: custom) }
  let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

  def can(policy, action, record = :record) = policy.new(user, record).public_send(action)

  it "grants what the custom role lists, and only that" do
    expect(can(Accounting::JournalEntryPolicy, :post?, entry)).to be true
    expect(can(Accounting::JournalEntryPolicy, :reverse?, entry)).to be false
    expect(can(Accounting::PartnerPolicy, :create?)).to be false
    expect(can(Accounting::ReportPolicy, :trial_balance?)).to be true
    expect(can(Accounting::Settings::BasePolicy, :index?)).to be false
  end

  it "ignores the system role of the access while a custom role is set" do
    membership.update_columns(role: UserEntity.roles[:admin])

    expect(can(Accounting::JournalEntryPolicy, :reverse?, entry)).to be false
  end

  it "gives back the system role's rights when the custom role is removed" do
    membership.update!(custom_role: nil, role: :accountant)

    expect(can(Accounting::JournalEntryPolicy, :reverse?, entry)).to be true
  end

  it "takes effect on the next request: a right removed from the role is gone at once" do
    expect { custom.update!(permissions: %w[records.view]) }.to change { can(Accounting::JournalEntryPolicy, :post?, entry) }.from(true).to(false)
  end

  it "a deactivated or expired access has no right, custom role or not" do
    membership.update!(active: false)

    expect(can(Accounting::JournalEntryPolicy, :post?, entry)).to be false
  end

  it "requires a second factor when the role can validate, unlock or administer" do
    expect(user.second_factor_required?).to be true

    custom.update!(permissions: %w[records.view reports.view])

    expect(user.reload.second_factor_required?).to be false
  end

  it "an API key of the person follows the custom role" do
    client = ApiClient.new(entity: entity, owner: user, name: "k", scopes: [])

    expect(client.owner_permits?("entries.post")).to be true
    expect(client.owner_permits?("records.write")).to be false
  end

  describe "the access" do
    it "never takes the owner role: a custom role is not an owner" do
      expect(build(:user_entity, :admin, custom_role: custom)).not_to be_valid
    end

    it "refuses a custom role of another entity" do
      foreign = ActsAsTenant.with_tenant(create(:entity)) { CustomRole.create!(name: "Theirs", permissions: %w[records.view]) }

      expect(membership.update(custom_role: foreign)).to be false
    end

    it "an unknown permission still raises, even for a person with a custom role" do
      expect { Accounting::JournalEntryPolicy.new(user, entry).send(:can?, "entries.typo") }.to raise_error(KeyError)
    end
  end
end
