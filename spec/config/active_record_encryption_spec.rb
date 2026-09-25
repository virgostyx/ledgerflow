require 'rails_helper'

# Per-entity Peppol credentials are stored with `encrypts`: this needs the encryption keys, set for development and
# test in config/environments and read from the credentials in production.
RSpec.describe 'Active Record encryption' do
  let(:encryptor) { ActiveRecord::Encryption.encryptor }

  it 'is configured: a value is unreadable once encrypted and comes back intact' do
    cipher = encryptor.encrypt('client-secret-123')

    expect(cipher).not_to include('client-secret-123')
    expect(encryptor.decrypt(cipher)).to eq('client-secret-123')
  end

  it 'gives a different ciphertext each time (not deterministic by default)' do
    expect(encryptor.encrypt('same value')).not_to eq(encryptor.encrypt('same value'))
  end
end
