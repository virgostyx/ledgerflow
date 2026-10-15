require "rails_helper"

# B03c étape 4, critères 6 et 12: Ed25519 signatures, with the public keys in the database and the private ones outside it; a retired key still verifies the old certificates;
# a revoked one is told; nothing secret in the database, the log or the repository.
RSpec.describe Ledger::SigningKeys do
  include_context "with signing keys directory"

  it "generates a key: the public part in the database, the private part in a file of its own, readable by the owner only" do
    key = described_class.generate!

    expect(key).to have_attributes(status: "active", algorithm: "Ed25519")
    expect(Base64.strict_decode64(key.public_key).bytesize).to eq(32)
    expect(key.fingerprint).to eq(Digest::SHA256.hexdigest(Base64.strict_decode64(key.public_key)))
    path = Pathname(signing_keys_directory).join("#{key.key_id}.pem")
    expect(path).to exist
    expect(path.stat.mode & 0o777).to eq(0o600)
  end

  it "signs, and the signature verifies with the public key alone" do
    key = described_class.generate!

    key_id, signature = described_class.sign("what is certified")

    expect(key_id).to eq(key.key_id)
    expect(described_class.verify(key.key_id, "what is certified", signature)).to be(true)
    expect(described_class.verify(key.key_id, "what is certified.", signature)).to be(false)
    expect(described_class.verify(key.key_id, "what is certified", signature.reverse)).to be(false)
  end

  it "verifies with the key a standard library would use: OpenSSL, from the raw public key" do
    key = described_class.generate!
    _, signature = described_class.sign("message")
    der = [ "302a300506032b6570032100" ].pack("H*") + Base64.strict_decode64(key.public_key) # the fixed header of an Ed25519 public key (RFC 8410)

    expect(OpenSSL::PKey.read(der).verify(nil, Base64.strict_decode64(signature), "message")).to be(true)
  end

  it "rotates: the new key signs, the old one is retired and still verifies what it signed" do
    old = described_class.generate!
    _, old_signature = described_class.sign("old certificate")

    new = described_class.rotate!

    expect(old.reload).to have_attributes(status: "retired", retired_at: be_present)
    expect(new.status).to eq("active")
    expect(described_class.sign("new certificate").first).to eq(new.key_id)
    expect(described_class.verify(old.key_id, "old certificate", old_signature)).to be(true)
    expect(Pathname(signing_keys_directory).join("#{old.key_id}.pem")).to exist # kept: a retired key may still have to be proved by the file, never deleted
  end

  it "has one active key at a time" do
    described_class.generate!

    expect { described_class.generate! }.not_to raise_error # generating again rotates
    expect(Ledger::SigningKey.where(status: "active").count).to eq(1)
  end

  it "revokes a key with a reason: it no longer signs, and says it is revoked" do
    key = described_class.generate!
    _, signature = described_class.sign("certificate")

    described_class.revoke!(key.key_id, reason: "the file was copied")

    expect(key.reload).to have_attributes(status: "revoked", revoked_at: be_present, revocation_reason: "the file was copied")
    expect { described_class.sign("anything") }.to raise_error(Ledger::SigningKeys::NoActiveKey)
    expect(described_class.verify(key.key_id, "certificate", signature)).to be(true) # the signature is genuine; what it is worth is told by the status
    expect(described_class.status_of(key.key_id)).to eq("revoked")
  end

  it "does not sign without an active key, nor with a key whose file is missing" do
    expect { described_class.sign("x") }.to raise_error(Ledger::SigningKeys::NoActiveKey)
    key = described_class.generate!
    File.delete(Pathname(signing_keys_directory).join("#{key.key_id}.pem"))

    expect { described_class.sign("x") }.to raise_error(Ledger::SigningKeys::PrivateKeyMissing)
  end

  it "publishes the public keys: identifier, algorithm, key, fingerprint, status, dates" do
    old = described_class.generate!
    new = described_class.rotate!

    published = described_class.published

    expect(published.map { |k| k["key_id"] }).to eq([ old.key_id, new.key_id ])
    expect(published.last).to include("algorithm" => "Ed25519", "public_key" => new.public_key, "fingerprint" => new.fingerprint, "status" => "active")
    expect(published.first).to include("status" => "retired")
    expect(published.to_json).not_to include("PRIVATE")
  end

  describe "no private key anywhere it should not be (critère 12)" do
    it "is not in the database: no column for it, and no row holds the key" do
      key = described_class.generate!
      private_pem = File.read(Pathname(signing_keys_directory).join("#{key.key_id}.pem"))
      private_raw = Base64.strict_encode64(OpenSSL::PKey.read(private_pem).raw_private_key)

      expect(Ledger::SigningKey.column_names).not_to include(a_string_matching(/private|secret/i))
      dump = Ledger::SigningKey.all.map(&:attributes).to_json
      expect(dump).not_to include("PRIVATE", private_raw)
      expect(dump).not_to include(private_pem.lines[1].strip)
    end

    it "is not in the log, whatever was done with the keys" do
      io = StringIO.new
      logger = ActiveSupport::Logger.new(io)
      key = nil
      Rails.logger.broadcast_to(logger) if Rails.logger.respond_to?(:broadcast_to)
      key = described_class.generate!
      described_class.sign("x")
      described_class.rotate!
      private_raw = Base64.strict_encode64(OpenSSL::PKey.read(File.read(Pathname(signing_keys_directory).join("#{key.key_id}.pem"))).raw_private_key)

      expect(io.string).not_to include("PRIVATE", private_raw)
      Rails.logger.stop_broadcasting_to(logger) if Rails.logger.respond_to?(:stop_broadcasting_to)
    end

    it "is not in the repository: no file that Git knows holds a private key" do
      tracked = `git ls-files`.split("\n").reject { |f| f.start_with?("spec/") || f.end_with?(".md") || !File.file?(f) }
      offenders = tracked.select { |file| File.binread(file).include?("-----BEGIN") && File.binread(file).match?(/-----BEGIN [A-Z ]*PRIVATE KEY-----/) }

      expect(offenders).to be_empty
    end

    it "does not appear among the parameters the logs keep: the parameter filter knows the names a key goes by" do
      filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

      expect(filter.filter("private_key" => "x", "signing_key" => "y", "ledger_private_key_pem" => "z", "name" => "kept")).to eq("private_key" => "[FILTERED]", "signing_key" => "[FILTERED]",
                                                                                                                           "ledger_private_key_pem" => "[FILTERED]", "name" => "kept")
    end
  end
end
