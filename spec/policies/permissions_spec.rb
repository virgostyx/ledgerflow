require "rails_helper"

# F01: the role x permission matrix is the single source of the rights; the policies only ask it.
RSpec.describe Permissions do
  include_context "with entity"

  ROLES = UserEntity.roles.keys.map(&:to_sym).freeze

  # Every permission of the matrix, with the policy actions that must obey it.
  ACTIONS = {
    "records.view"           => [ [ Accounting::PartnerPolicy, :show? ] ],
    "records.list"           => [ [ Accounting::PartnerPolicy, :index? ] ],
    "records.write"          => [ [ Accounting::PartnerPolicy, :create? ], [ Accounting::PartnerPolicy, :update? ] ],
    "records.delete"         => [ [ Accounting::PartnerPolicy, :destroy? ], [ Accounting::Settings::BasePolicy, :destroy? ] ],
    "entries.post"           => [ [ Accounting::JournalEntryPolicy, :post? ] ],
    "entries.reverse"        => [ [ Accounting::JournalEntryPolicy, :reverse? ] ],
    "invoices.issue"         => [ [ Accounting::InvoicePolicy, :post? ], [ Accounting::InvoicePolicy, :send_peppol? ], [ Accounting::InvoicePolicy, :send_email? ] ],
    "reconciliations.manage" => [ [ Accounting::BankReconciliationsPolicy, :show? ], [ Accounting::BankReconciliationsPolicy, :update? ] ],
    "vat.file"               => [ [ Accounting::VatDeclarationPolicy, :submit? ], [ Accounting::VatDeclarationPolicy, :accept? ], [ Accounting::FiscalYearPolicy, :vat_regularization? ] ],
    "payments.manage"        => [ [ Accounting::PaymentBatchPolicy, :generate? ], [ Accounting::PaymentBatchPolicy, :execute? ] ],
    "dunning.send"           => [ [ Accounting::PaymentReminderPolicy, :index? ] ],
    "periods.lock"           => [ [ Accounting::PeriodLockPolicy, :create? ], [ Accounting::PeriodLockPolicy, :new? ] ],
    "periods.unlock"         => [ [ Accounting::PeriodLockPolicy, :unlock? ] ],
    "users.manage"           => [ [ UserEntityPolicy, :index? ], [ UserEntityPolicy, :create? ], [ UserEntityPolicy, :update? ] ],
    "settings.manage"        => [ [ Accounting::Settings::BasePolicy, :index? ], [ Accounting::Settings::BasePolicy, :update? ] ],
    "closing.adjust"         => [ [ Accounting::FiscalYearPolicy, :propose_revaluation? ], [ Accounting::AccrualPolicy, :index? ], [ Accounting::ConsistencyRunPolicy, :acknowledge? ] ],
    "fiscal_years.manage"    => [ [ Accounting::FiscalYearPolicy, :close? ], [ Accounting::FiscalYearPolicy, :create? ], [ Accounting::FiscalYearPolicy, :update? ] ],
    "reports.view"           => [ [ Accounting::ReportPolicy, :trial_balance? ] ],
    "audit.view"             => [ [ Accounting::AuditLogPolicy, :index? ], [ Accounting::ClosingBundlePolicy, :show? ], [ Accounting::ConsistencyRunPolicy, :index? ] ]
  }.freeze

  def user_in_entity(role)
    # the global role is deliberately the opposite of what the matrix grants: it must not matter
    create(:user, role: :admin).tap { |user| create(:user_entity, user: user, entity: entity, role: role) }
  end

  it "has an action under test for every permission, and no permission unknown to the matrix" do
    expect(ACTIONS.keys).to match_array(described_class::MATRIX.keys)
  end

  it "only names roles an entity membership can hold" do
    expect(described_class::MATRIX.values.flatten.uniq - ROLES).to be_empty
  end

  it "denies everything to a missing role" do
    expect(described_class::MATRIX.keys.none? { |permission| described_class.allowed?(nil, permission) }).to be true
  end

  it "refuses a permission it does not know rather than denying it silently" do
    expect { described_class.allowed?(:admin, "entries.typo") }.to raise_error(KeyError)
  end

  ACTIONS.each do |permission, actions|
    actions.each do |policy, action|
      describe "#{permission} through #{policy}##{action}" do
        ROLES.each do |role|
          it "#{described_class::MATRIX.fetch(permission).include?(role) ? 'allows' : 'denies'} #{role}" do
            expected = described_class::MATRIX.fetch(permission).include?(role)

            expect(policy.new(user_in_entity(role), :record).public_send(action)).to eq(expected)
          end
        end

        it "denies a user with no membership in the entity" do
          expect(policy.new(create(:user, role: :admin), :record).public_send(action)).to be false
        end
      end
    end
  end
end
