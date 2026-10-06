require "rails_helper"

# The last check on what the model wrote, before anyone sees it (A03): no address it could use to carry data out, no key or token.
RSpec.describe Agent::ResponseGuard do
  def clean(text) = described_class.clean(text)

  it "takes an address out, whatever the way it is written" do
    text, kinds = clean("See https://evil.example/collect?d=12 and www.evil.example/x, or ![i](http://evil.example/p.png)")

    expect(text).not_to match(/evil\.example/)
    expect(text).to include("[link removed]")
    expect(kinds).to eq([ :url_removed ])
  end

  {
    "an Anthropic key"      => "key sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 here",
    "an OpenAI-style key"   => "key sk-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 here",
    "an AWS access key"     => "key AKIAABCDEFGHIJKLMNOP here",
    "an API key of the app" => "key lf_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789_- here",
    "a webhook secret"      => "key whsec_AbCdEfGhIjKlMnOpQrStUvWxYz0123456789 here",
    "a bearer token"        => "Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789 done",
    "a JWT"                 => "token eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk here",
    "a private key block"   => "-----BEGIN RSA PRIVATE KEY-----\nMIIEow\n-----END RSA PRIVATE KEY-----"
  }.each do |name, text|
    it "takes out #{name}" do
      cleaned, kinds = clean(text)

      expect(cleaned).to include("[secret removed]")
      expect(cleaned).not_to match(/sk-ant|sk-Ab|AKIA|lf_Ab|whsec_|abcdefghijklmnopqrstuvwxyz0123|eyJ|MIIEow/)
      expect(kinds).to eq([ :secret_removed ])
    end
  end

  it "says both when both were there" do
    _, kinds = clean("https://x.example and sk-ant-api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789")

    expect(kinds).to contain_exactly(:url_removed, :secret_removed)
  end

  it "leaves an ordinary answer exactly as it is, amounts and references included" do
    text = "Au 26/09/2026, le solde du compte 400000 est de 12 345,00 EUR (voir [[ref:R04:2026-09-26:customer:total]]). Contactez support@firm.test si besoin."

    expect(clean(text)).to eq([ text, [] ])
  end

  it "answers an empty text for nothing" do
    expect(clean(nil)).to eq([ "", [] ])
  end
end
