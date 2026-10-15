# B03c: a directory of its own for the private keys of a spec, removed afterwards: nothing of what a spec signs with is kept.
RSpec.shared_context "with signing keys directory" do
  let(:signing_keys_directory) { Dir.mktmpdir("ledger-keys") }

  around do |example|
    previous = Rails.configuration.x.ledger_signing_key_dir
    Rails.configuration.x.ledger_signing_key_dir = signing_keys_directory
    example.run
  ensure
    Rails.configuration.x.ledger_signing_key_dir = previous
    FileUtils.rm_rf(signing_keys_directory)
  end
end
