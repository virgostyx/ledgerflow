require 'rails_helper'

RSpec.describe Entities::ProvisionEntity, type: :service do
  let(:user)   { create(:user) }
  let(:entity) { create(:entity, created_by: user) }

  subject(:result) { described_class.call(entity: entity, created_by: user) }

  it 'succeeds' do
    expect(result).to be_success
  end

  it 'creates an admin UserEntity membership for the creator' do
    expect { result }.to change(UserEntity, :count).by(1)
    membership = UserEntity.find_by(user: user, entity: entity)
    expect(membership).to be_admin
  end

  it 'copies the PCMN chart of accounts' do
    expect {
      result
    }.to change {
      ActsAsTenant.with_tenant(entity) { Accounting::Account.count }
    }.by_at_least(200)
  end

  it 'creates default journals' do
    expect {
      result
    }.to change {
      ActsAsTenant.with_tenant(entity) { Accounting::Journal.count }
    }.by_at_least(4)
  end

  it 'creates default analytical axes' do
    expect {
      result
    }.to change {
      ActsAsTenant.with_tenant(entity) { Accounting::AnalyticalAxis.count }
    }.by_at_least(1)
  end

  it 'creates an open fiscal year for the current year' do
    result
    fy = ActsAsTenant.with_tenant(entity) { Accounting::FiscalYear.open_years.first }
    expect(fy).to be_present
    expect(fy.year).to eq(Date.current.year)
  end

  context 'when admin membership creation fails' do
    before do
      allow(UserEntity).to receive(:create!).and_raise(StandardError, 'DB error')
    end

    it 'returns a failed context' do
      expect(result).to be_failure
    end
  end
end
