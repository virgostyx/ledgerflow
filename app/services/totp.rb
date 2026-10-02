# Time-based one-time passwords, RFC 6238 (SHA-1, 6 digits, 30 s): what an authenticator app computes.
# ponytail: stdlib only (OpenSSL HMAC); the base32 helpers below are the only "library" code.
module Totp
  STEP   = 30
  DIGITS = 6
  ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

  # 160 bits, base32: what the user types or scans into the app.
  def self.generate_secret = encode32(SecureRandom.random_bytes(20))

  def self.code(secret, time = Time.now) = hotp(decode32(secret), time.to_i / STEP)

  # The time step the code belongs to, or nil. One step of drift either way; a step at or before `after_step`
  # (the last one accepted) is refused, so a code cannot be used twice.
  def self.verify(secret, code, at: Time.now, after_step: nil, drift: 1)
    code = code.to_s.delete(" ")
    return nil unless code.match?(/\A\d{#{DIGITS}}\z/)

    key = decode32(secret)
    current = at.to_i / STEP
    ((current - drift)..(current + drift)).find do |step|
      (after_step.nil? || step > after_step) && ActiveSupport::SecurityUtils.secure_compare(hotp(key, step), code)
    end
  end

  def self.provisioning_uri(secret, account:, issuer:)
    label = "#{ERB::Util.url_encode(issuer)}:#{ERB::Util.url_encode(account)}"
    "otpauth://totp/#{label}?secret=#{secret}&issuer=#{ERB::Util.url_encode(issuer)}&algorithm=SHA1&digits=#{DIGITS}&period=#{STEP}"
  end

  def self.hotp(key, counter)
    hmac = OpenSSL::HMAC.digest("SHA1", key, [ counter ].pack("Q>"))
    offset = hmac.bytes.last & 0x0f
    (hmac[offset, 4].unpack1("N") & 0x7fffffff).modulo(10**DIGITS).to_s.rjust(DIGITS, "0")
  end

  def self.encode32(bytes)
    bits = bytes.unpack1("B*")
    bits += "0" * (-bits.size % 5)
    bits.scan(/.{5}/).map { |chunk| ALPHABET[chunk.to_i(2)] }.join
  end

  def self.decode32(text)
    bits = text.to_s.upcase.delete("=").chars.map { |char| ALPHABET.index(char).to_s(2).rjust(5, "0") }.join
    [ bits[0, bits.size / 8 * 8] ].pack("B*")
  end

  private_class_method :hotp, :encode32, :decode32
end
