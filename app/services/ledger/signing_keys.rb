# B03c: the Ed25519 keys that sign the certificates (OpenSSL, standard library). The public part is in the database and is published; the private part is a file in a directory
# outside the application, `LEDGER_SIGNING_KEY_DIR` (mounted by the deployment, not part of the image and not of a backup that is not encrypted), one file per key, readable by its
# owner only. It never goes into the repository, the database, a log, an answer or a parameter.
#
# A key is `active` (one at a time: it signs), `retired` (it was replaced: it only verifies, and its file is kept) or `revoked` (it was compromised: it only verifies, its file is
# removed, and what it signed carries the word). A key is never deleted.
module Ledger::SigningKeys
  class NoActiveKey < StandardError; end
  class PrivateKeyMissing < StandardError; end
  class NotConfigured < StandardError; end

  # The fixed header of the DER form of an Ed25519 public key (RFC 8410), before its 32 bytes.
  PUBLIC_KEY_HEADER = [ "302a300506032b6570032100" ].pack("H*").freeze

  def self.directory
    path = Rails.configuration.x.ledger_signing_key_dir.presence or raise NotConfigured, "LEDGER_SIGNING_KEY_DIR is not set: the private keys have nowhere to live"
    Pathname(path)
  end

  # A new key, active; the one that was active is retired.
  def self.generate!
    key = OpenSSL::PKey.generate_key("ED25519")
    public_raw = key.raw_public_key
    key_id = "lk-#{Time.now.utc.strftime('%Y%m%d')}-#{SecureRandom.hex(4)}"
    Ledger::SigningKey.transaction do
      retire_active!
      write_private(key_id, key.private_to_pem)
      Ledger::SigningKey.create!(key_id: key_id, public_key: Base64.strict_encode64(public_raw), fingerprint: Digest::SHA256.hexdigest(public_raw), status: "active")
    end
  end

  def self.rotate! = generate!

  def self.revoke!(key_id, reason:)
    raise ArgumentError, "a reason is needed to revoke a key" if reason.blank?

    key = Ledger::SigningKey.find_by!(key_id: key_id)
    key.update!(status: "revoked", revoked_at: Time.current, revocation_reason: reason)
    FileUtils.rm_f(private_path(key_id))
    key
  end

  # => [key_id, signature in base64]
  def self.sign(message)
    key = Ledger::SigningKey.find_by(status: "active") or raise NoActiveKey, "no active signing key"
    path = private_path(key.key_id)
    raise PrivateKeyMissing, "the private file of key #{key.key_id} is not in the signing directory" unless path.file?

    [ key.key_id, Base64.strict_encode64(OpenSSL::PKey.read(path.read).sign(nil, message.to_s)) ]
  end

  # Whether the signature is genuine for that key, whatever its status (what a status means is told by `status_of`).
  def self.verify(key_id, message, signature)
    key = Ledger::SigningKey.find_by(key_id: key_id) or return false
    public_key(key).verify(nil, Base64.strict_decode64(signature), message.to_s)
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    false
  end

  def self.public_key(key) = OpenSSL::PKey.read(PUBLIC_KEY_HEADER + Base64.strict_decode64(key.public_key))

  def self.status_of(key_id) = Ledger::SigningKey.find_by(key_id: key_id)&.status

  # What is published at /.well-known/ledgerflow/keys.json.
  def self.published
    Ledger::SigningKey.chronological.map do |key|
      { "key_id" => key.key_id, "algorithm" => key.algorithm, "public_key" => key.public_key, "fingerprint" => key.fingerprint, "status" => key.status,
        "created_at" => key.created_at.utc.iso8601, "retired_at" => key.retired_at&.utc&.iso8601, "revoked_at" => key.revoked_at&.utc&.iso8601 }
    end
  end

  def self.retire_active!
    Ledger::SigningKey.where(status: "active").update_all(status: "retired", retired_at: Time.current, updated_at: Time.current)
  end
  private_class_method :retire_active!

  def self.private_path(key_id) = directory.join("#{key_id}.pem")
  private_class_method :private_path

  def self.write_private(key_id, pem)
    FileUtils.mkdir_p(directory, mode: 0o700)
    File.open(private_path(key_id), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(pem) }
  end
  private_class_method :write_private
end
