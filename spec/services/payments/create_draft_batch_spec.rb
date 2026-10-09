require 'rails_helper'

RSpec.describe Payments::CreateDraftBatch do
  include_context 'with entity'

  let(:bank_account) { create(:bank_account) }
  let(:supplier)      { create(:partner, :supplier, :with_iban) }
  let(:fiscal_year)   { create(:fiscal_year, status: :open) }
  let(:invoice) do
    create(:invoice, :supplier, :posted, :with_lines, partner: supplier, fiscal_year: fiscal_year)
  end

  describe '.call' do
    it 'creates a draft payment batch from eligible invoices' do
      result = described_class.call(
        invoice_ids: [ invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_success
      batch = result.payment_batch
      expect(batch).to be_draft
      expect(batch.lines.sole.invoice).to eq(invoice)
    end

    it 'rolls back and fails when an invoice is not eligible' do
      draft_invoice = create(:invoice, :supplier, :draft, :with_lines, partner: supplier, fiscal_year: fiscal_year)

      result = described_class.call(
        invoice_ids: [ draft_invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_failure
      expect(Accounting::PaymentBatch.count).to eq(0)
    end

    # B01a criterion 8: an invoice that has not gone through its approval circuit is not paid
    describe 'the approval of the invoice (B01a)' do
      def batch_of(invoice) = described_class.call(invoice_ids: [ invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1)

      it 'refuses an invoice that waits for approval, is on hold or is disputed, and says why' do
        %i[to_approve on_hold disputed].each do |status|
          invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[status])

          result = batch_of(invoice)

          expect(result).to be_failure, status.to_s
          expect(result.message).to match(/approval|hold|dispute/i)
        end
        expect(Accounting::PaymentBatch.count).to eq(0)
      end

      it 'takes an invoice that is approved, or that needs no approval' do
        %i[approved not_required].each do |status|
          invoice.update_columns(payment_status: Accounting::Invoice.payment_statuses[status])
          result = batch_of(invoice)

          expect(result).to be_success, status.to_s
          result.payment_batch.destroy!
        end
      end

      it 'refuses an approval that no longer matches the invoice (it was changed since)' do
        entity.update!(features: entity.features.merge('b01a' => true))
        policy = Approvals::Policy.create!(name: 'all', subject: :purchase_invoice, priority: 1)
        policy.steps.create!(position: 1, mode: :any_of, approver_roles: %w[admin])
        request = Approvals::Submit.call(invoice: invoice, user: nil)[:request]
        owner = create(:user).tap { |u| create(:user_entity, :admin, user: u, entity: entity) }
        Approvals::Decide.call(request: request, user: owner, decision: :approved, content_fingerprint: request.content_fingerprint)
        expect(batch_of(invoice)).to be_success.and(satisfy { |r| r.payment_batch.destroy! })

        invoice.lines.first.update!(unit_price: '9999.00') # invalidates the approval: the circuit starts again

        expect(batch_of(invoice)).to be_failure
      end
    end

    it 'refuses a foreign-currency invoice (SEPA pays in EUR only)' do
      invoice.update_columns(currency: 'USD')

      result = described_class.call(
        invoice_ids: [ invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_failure
      expect(result.message).to include('USD')
      expect(Accounting::PaymentBatch.count).to eq(0)
    end

    it 'refuses a non-EUR bank account as SEPA debtor' do
      bank_account.update_columns(currency: 'USD')

      result = described_class.call(
        invoice_ids: [ invoice.id ], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_failure
      expect(Accounting::PaymentBatch.count).to eq(0)
    end

    it 'does not persist a batch when no invoices are given' do
      result = described_class.call(
        invoice_ids: [], bank_account: bank_account, requested_execution_date: Date.current + 1
      )

      expect(result).to be_failure
      expect(Accounting::PaymentBatch.count).to eq(0)
    end
  end
end
