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
    "entries.post"           => [ [ Accounting::JournalEntryPolicy, :post? ], [ Accounting::BankReconciliationsPolicy, :post? ] ],
    "entries.reverse"        => [ [ Accounting::JournalEntryPolicy, :reverse? ] ],
    "peppol.review"          => [ [ Accounting::PeppolMessagePolicy, :index? ], [ Accounting::PeppolMessagePolicy, :reprocess? ] ],
    "peppol.send"            => [ [ Accounting::PeppolMessagePolicy, :resend? ], [ Accounting::InvoicePolicy, :send_peppol? ] ],
    "peppol.configure"       => [ [ Accounting::PeppolMessagePolicy, :configure? ] ],
    "entry_templates.manage" => [ [ Accounting::EntryTemplatePolicy, :create? ], [ Accounting::EntryTemplatePolicy, :index? ] ],
    "recurring.manage"       => [ [ Accounting::RecurringEntryPolicy, :create? ], [ Accounting::RecurringEntryPolicy, :pause? ] ],
    "recurring.approve_post" => [ [ Accounting::RecurringEntryPolicy, :approve_post? ] ],
    "invoices.issue"         => [ [ Accounting::InvoicePolicy, :post? ], [ Accounting::InvoicePolicy, :send_peppol? ], [ Accounting::InvoicePolicy, :send_email? ] ],
    "reconciliations.manage" => [ [ Accounting::BankReconciliationsPolicy, :show? ], [ Accounting::BankReconciliationsPolicy, :update? ] ],
    "vat.file"               => [ [ Accounting::VatDeclarationPolicy, :submit? ], [ Accounting::VatDeclarationPolicy, :accept? ], [ Accounting::FiscalYearPolicy, :vat_regularization? ] ],
    "payments.manage"        => [ [ Accounting::PaymentBatchPolicy, :generate? ], [ Accounting::PaymentBatchPolicy, :execute? ] ],
    "dunning.send"           => [ [ Accounting::PaymentReminderPolicy, :index? ] ],
    "periods.lock"           => [ [ Accounting::PeriodLockPolicy, :create? ], [ Accounting::PeriodLockPolicy, :new? ] ],
    "periods.unlock"         => [ [ Accounting::PeriodLockPolicy, :unlock? ] ],
    "users.manage"           => [ [ UserEntityPolicy, :index? ], [ UserEntityPolicy, :create? ], [ UserEntityPolicy, :update? ], [ UserEntityPolicy, :reset_two_factor? ], [ CustomRolePolicy, :index? ], [ CustomRolePolicy, :create? ], [ CustomRolePolicy, :update? ], [ CustomRolePolicy, :destroy? ] ],
    "settings.manage"        => [ [ Accounting::Settings::BasePolicy, :index? ], [ Accounting::Settings::BasePolicy, :update? ] ],
    "closing.adjust"         => [ [ Accounting::FiscalYearPolicy, :propose_revaluation? ], [ Accounting::AccrualPolicy, :index? ], [ Accounting::ConsistencyRunPolicy, :acknowledge? ] ],
    "fiscal_years.manage"    => [ [ Accounting::FiscalYearPolicy, :close? ], [ Accounting::FiscalYearPolicy, :create? ], [ Accounting::FiscalYearPolicy, :update? ] ],
    "documents.view"         => [ [ Accounting::DocumentPolicy, :index? ], [ Accounting::DocumentPolicy, :show? ], [ Accounting::DocumentPolicy, :download? ] ],
    "documents.upload"       => [ [ Accounting::DocumentPolicy, :create? ], [ Accounting::DocumentPolicy, :new? ], [ Accounting::DocumentPolicy, :rerun? ], [ Accounting::DocumentPolicy, :split? ] ],
    "documents.link"         => [ [ Accounting::DocumentPolicy, :link? ], [ Accounting::DocumentPolicy, :unlink? ], [ Accounting::DocumentPolicy, :update? ], [ Accounting::DocumentPolicy, :confirm_field? ], [ Accounting::DocumentPolicy, :create_invoice? ] ],
    "documents.archive"      => [ [ Accounting::DocumentPolicy, :archive? ] ],
    "documents.delete_expired" => [ [ Accounting::DocumentPolicy, :destroy? ], [ Accounting::DocumentPolicy, :legal_hold? ] ],
    "reconciliations.cross_partner" => [ [ Accounting::LetteringPolicy, :cross_partner? ] ],
    "reconciliations.unreconcile_locked" => [ [ Accounting::LetteringPolicy, :unreconcile_locked? ] ],
    "bank.import"            => [ [ Accounting::BankStatementPolicy, :import? ] ],
    "bank.match"             => [ [ Accounting::BankStatementPolicy, :match? ] ],
    "reports.view"           => [ [ Accounting::ReportPolicy, :trial_balance? ] ],
    "reports.export"         => [ [ Accounting::ReportPolicy, :export? ] ],
    "reports.export_readonly" => [ [ Accounting::ReportPolicy, :export_readonly? ] ],
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
