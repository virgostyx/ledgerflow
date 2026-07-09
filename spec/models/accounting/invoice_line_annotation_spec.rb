require 'rails_helper'

RSpec.describe Accounting::InvoiceLineAnnotation, type: :model do
  include_context 'with entity'

  let(:axis)    { create(:analytical_axis) }
  let(:account) { create(:analytical_account, analytical_axis: axis) }
  let(:other_axis) { create(:analytical_axis) }
  let(:other_account) { create(:analytical_account, analytical_axis: other_axis) }

  let(:invoice_line) { create(:invoice_line) }

  describe 'associations' do
    it { should belong_to(:invoice_line).class_name('Accounting::InvoiceLine') }
    it { should belong_to(:analytical_axis).class_name('Accounting::AnalyticalAxis') }
    it { should belong_to(:analytical_account).class_name('Accounting::AnalyticalAccount') }
  end

  describe 'validations' do
    subject do
      build(:invoice_line_annotation, invoice_line: invoice_line,
            analytical_axis: axis, analytical_account: account)
    end

    it { should be_valid }

    it 'interdit deux annotations pour le même axe sur la même ligne' do
      create(:invoice_line_annotation, invoice_line: invoice_line,
             analytical_axis: axis, analytical_account: account)
      duplicate = build(:invoice_line_annotation, invoice_line: invoice_line,
                        analytical_axis: axis, analytical_account: account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:analytical_axis_id]).to be_present
    end

    it 'rejette un compte qui n appartient pas à l axe' do
      wrong = build(:invoice_line_annotation, invoice_line: invoice_line,
                    analytical_axis: axis, analytical_account: other_account)
      expect(wrong).not_to be_valid
      expect(wrong.errors[:analytical_account]).to be_present
    end

    it 'autorise deux annotations pour des axes différents sur la même ligne' do
      create(:invoice_line_annotation, invoice_line: invoice_line,
             analytical_axis: axis, analytical_account: account)
      other = build(:invoice_line_annotation, invoice_line: invoice_line,
                    analytical_axis: other_axis, analytical_account: other_account)
      expect(other).to be_valid
    end
  end
end
