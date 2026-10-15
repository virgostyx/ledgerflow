require "base64"
require "digest"
require "json"
require "openssl"
require "open3"
require "tempfile"
require_relative "canonical"
require_relative "merkle"
require_relative "audit_chain"
require_relative "zip_reader"

# The decryption of a package that was protected by a passphrase: "LFPKG1" || salt (16) || iv (12) || tag (16) || ciphertext, AES-256-GCM, the key from PBKDF2-HMAC-SHA256.
module LedgerVerify
  module Package
    MAGIC = "LFPKG1".b
    ITERATIONS = 600_000

    class WrongPassphrase < StandardError; end

    def self.encrypted?(data) = data.b.start_with?(MAGIC)

    def self.encrypt(data, passphrase)
      salt = OpenSSL::Random.random_bytes(16)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = OpenSSL::KDF.pbkdf2_hmac(passphrase, salt: salt, iterations: ITERATIONS, length: 32, hash: "sha256")
      iv = cipher.random_iv
      ciphertext = cipher.update(data.b) + cipher.final
      MAGIC + salt + iv + cipher.auth_tag + ciphertext
    end

    def self.decrypt(data, passphrase)
      data = data.b
      salt, iv, tag, ciphertext = data[MAGIC.bytesize, 16], data[MAGIC.bytesize + 16, 12], data[MAGIC.bytesize + 28, 16], data[(MAGIC.bytesize + 44)..]
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = OpenSSL::KDF.pbkdf2_hmac(passphrase, salt: salt, iterations: ITERATIONS, length: 32, hash: "sha256")
      cipher.iv = iv
      cipher.auth_tag = tag
      cipher.update(ciphertext) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      raise WrongPassphrase, "the passphrase is wrong, or the package was altered"
    end
  end
end
