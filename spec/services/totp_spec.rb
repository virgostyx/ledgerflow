require "rails_helper"

# RFC 6238 appendix B (SHA-1): the secret is the ASCII string "12345678901234567890"; the RFC lists 8 digits,
# an authenticator app shows the last 6.
RSpec.describe Totp do
  let(:secret) { "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ" } # base32 of "12345678901234567890"

  {
    59            => "287082",
    1_111_111_109 => "081804",
    1_111_111_111 => "050471",
    1_234_567_890 => "005924",
    2_000_000_000 => "279037",
    20_000_000_000 => "353130"
  }.each do |seconds, expected|
    it "gives #{expected} at t=#{seconds} (RFC 6238 vector)" do
      expect(described_class.code(secret, Time.at(seconds))).to eq(expected)
    end
  end

  describe ".generate_secret" do
    it "is 160 bits of base32, different every time" do
      a = described_class.generate_secret
      b = described_class.generate_secret

      expect(a).to match(/\A[A-Z2-7]{32}\z/)
      expect(a).not_to eq(b)
    end
  end

  describe ".verify" do
    let(:now)  { Time.at(1_111_111_111) }
    let(:step) { now.to_i / 30 }

    it "accepts the current code and returns its time step" do
      expect(described_class.verify(secret, "050471", at: now)).to eq(step)
    end

    it "accepts the previous and the next step (clock drift of one step)" do
      expect(described_class.verify(secret, described_class.code(secret, now - 30), at: now)).to eq(step - 1)
      expect(described_class.verify(secret, described_class.code(secret, now + 30), at: now)).to eq(step + 1)
    end

    it "refuses a code two steps away" do
      expect(described_class.verify(secret, described_class.code(secret, now - 60), at: now)).to be_nil
      expect(described_class.verify(secret, described_class.code(secret, now + 60), at: now)).to be_nil
    end

    it "refuses a wrong code, a short one, a blank one and a non-numeric one" do
      [ "000000", "05047", "", nil, "abcdef", "0504711" ].each do |bad|
        expect(described_class.verify(secret, bad, at: now)).to be_nil
      end
    end

    it "refuses a code that was already used (replay), even inside the drift window" do
      expect(described_class.verify(secret, "050471", at: now, after_step: step)).to be_nil
      expect(described_class.verify(secret, "050471", at: now, after_step: step - 1)).to eq(step)
    end

    it "tolerates spaces in the typed code, as authenticator apps display them" do
      expect(described_class.verify(secret, "050 471", at: now)).to eq(step)
    end
  end

  describe ".provisioning_uri" do
    it "is the otpauth URI an authenticator app reads from the QR code" do
      uri = described_class.provisioning_uri(secret, account: "alice@example.com", issuer: "LedgerFlow")

      expect(uri).to eq("otpauth://totp/LedgerFlow:alice%40example.com?secret=#{secret}&issuer=LedgerFlow&algorithm=SHA1&digits=6&period=30")
    end
  end
end
