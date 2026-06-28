RSpec.shared_context 'with entity' do
  let(:entity) { create(:entity) }

  around(:each) { |ex| ActsAsTenant.with_tenant(entity) { ex.run } }
end
