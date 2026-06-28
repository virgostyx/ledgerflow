RSpec.configure do |config|
  config.around(:each) do |example|
    previous_tenant = ActsAsTenant.current_tenant
    ActsAsTenant.current_tenant = nil
    example.run
  ensure
    ActsAsTenant.current_tenant = previous_tenant
  end
end
