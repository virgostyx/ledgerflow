require "rails_helper"

# F01: rights come from the user's role in the CURRENT entity, never from the global users.role.
RSpec.describe "Policies use the role held in the current entity" do
  include_context "with entity"

  # [policy class, record, action, entity roles allowed]
  CASES = [
    [ Accounting::JournalEntryPolicy,     :entry,    :post?,                 %i[admin accountant] ],
    [ Accounting::JournalEntryPolicy,     :entry,    :reverse?,              %i[admin accountant] ],
    [ Accounting::InvoicePolicy,          :invoice,  :post?,                 %i[admin accountant] ],
    [ Accounting::InvoicePolicy,          :invoice,  :send_peppol?,          %i[admin accountant] ],
    [ Accounting::FiscalYearPolicy,       :year,     :close?,                %i[admin] ],
    [ Accounting::ReportPolicy,           :report,   :trial_balance?,        %i[admin accountant assistant manager auditor] ],
    [ Accounting::Settings::BasePolicy,   :settings, :index?,                %i[admin accountant] ],
    [ Accounting::Settings::BasePolicy,   :settings, :destroy?,              %i[admin] ],
    [ Accounting::BankReconciliationsPolicy, :bank,  :update?,               %i[admin accountant assistant] ]
  ].freeze

  def user_with(global_role:, entity_role: nil)
    create(:user, role: global_role).tap do |user|
      create(:user_entity, user: user, entity: entity, role: entity_role) if entity_role
    end
  end

  CASES.each do |policy, record, action, allowed|
    describe "#{policy}##{action}" do
      UserEntity.roles.keys.map(&:to_sym).each do |entity_role|
        it "#{allowed.include?(entity_role) ? 'allows' : 'denies'} a #{entity_role} of the entity, whatever the global role" do
          # the global role is the opposite of what the entity role should yield
          global = allowed.include?(entity_role) ? :auditor : :admin
          user = user_with(global_role: global, entity_role: entity_role)

          expect(policy.new(user, record).public_send(action)).to eq(allowed.include?(entity_role))
        end
      end

      it "denies a user with no membership in the entity, even with a global admin role" do
        user = user_with(global_role: :admin)

        expect(policy.new(user, record).public_send(action)).to be false
      end
    end
  end

  describe "an access that is no longer valid" do
    let(:policy) { Accounting::JournalEntryPolicy }

    it "denies an expired membership, even for an admin" do
      user = create(:user)
      create(:user_entity, :admin, user: user, entity: entity, valid_until: Date.current - 1)
      create(:user_entity, :admin, entity: entity) # another owner keeps the entity valid

      expect(policy.new(user, :entry).post?).to be false
    end

    it "denies a deactivated membership" do
      user = create(:user)
      create(:user_entity, :admin, entity: entity)
      create(:user_entity, :admin, user: user, entity: entity, active: false)

      expect(policy.new(user, :entry).post?).to be false
    end
  end
end
