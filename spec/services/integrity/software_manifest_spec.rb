require 'rails_helper'

# B03c: the revision a certificate names. In the container there is no .git: Kamal gives the version of the deployment in KAMAL_VERSION.
RSpec.describe Integrity::SoftwareManifest do
  def with_env(values)
    saved = values.keys.to_h { |name| [ name, ENV[name] ] }
    values.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| ENV[name] = value }
  end

  it 'takes GIT_REVISION first' do
    with_env('GIT_REVISION' => 'abc1234', 'KAMAL_VERSION' => 'ffffffff') { expect(described_class.revision).to eq('abc1234') }
  end

  it 'takes the version of the Kamal deployment when there is no GIT_REVISION' do
    with_env('GIT_REVISION' => nil, 'KAMAL_VERSION' => '8491c88deadbeef') { expect(described_class.revision).to eq('8491c88deadbeef') }
  end

  it 'asks git last, in a checkout' do
    with_env('GIT_REVISION' => nil, 'KAMAL_VERSION' => nil) { expect(described_class.revision).to match(/\A\h{7,}\z/) }
  end
end
