require "rails_helper"

RSpec.describe Webhooks::Signature do
  let(:body) { '{"event":"entry.posted"}' }
  let(:secret) { "whsec_test" }
  let(:now) { 1_800_000_000 }

  it "is verified by the receiver with the secret, from the raw body (criterion 7)" do
    header = described_class.header(secret, body, timestamp: now)
    expect(header).to match(/\At=1800000000,v1=\h{64}\z/)
    expect(described_class.verify(secret, header, body, now: now)).to be(true)
  end

  it "rejects a forged signature: another secret, another body, a missing or malformed header" do
    header = described_class.header(secret, body, timestamp: now)
    expect(described_class.verify("whsec_other", header, body, now: now)).to be(false)
    expect(described_class.verify(secret, header, body + " ", now: now)).to be(false)
    expect(described_class.verify(secret, header.sub(/v1=\h/, "v1=0"), body, now: now)).to be(false)
    expect(described_class.verify(secret, nil, body, now: now)).to be(false)
    expect(described_class.verify(secret, "garbage", body, now: now)).to be(false)
    expect(described_class.verify(secret, "t=#{now}", body, now: now)).to be(false)
  end

  it "rejects a delivery that is too old: a captured one cannot be sent again" do
    header = described_class.header(secret, body, timestamp: now)
    expect(described_class.verify(secret, header, body, now: now + 4.minutes.to_i)).to be(true)
    expect(described_class.verify(secret, header, body, now: now + 6.minutes.to_i)).to be(false)
    expect(described_class.verify(secret, header, body, now: now - 6.minutes.to_i)).to be(false)
  end

  it "signs with every secret it is given, so that a receiver can change over after a rotation" do
    header = described_class.header([ "new", "old" ], body, timestamp: now)
    expect(header.scan("v1=").size).to eq(2)
    expect(described_class.verify("new", header, body, now: now)).to be(true)
    expect(described_class.verify("old", header, body, now: now)).to be(true)
  end
end

RSpec.describe Webhooks::UrlGuard do
  def resolving(host, *addresses) = allow(Resolv).to receive(:getaddresses).with(host).and_return(addresses)

  it "accepts an https URL that names a public address" do
    resolving("hooks.example.com", "93.184.216.34")
    uri, ip = described_class.resolve!("https://hooks.example.com/in")
    expect([ uri.host, ip ]).to eq([ "hooks.example.com", "93.184.216.34" ])
  end

  it "refuses http, credentials, a missing host and a URL that is not one" do
    expect { described_class.check_syntax("http://hooks.example.com") }.to raise_error(described_class::Refused, /https/)
    expect { described_class.check_syntax("https://user:pw@hooks.example.com") }.to raise_error(described_class::Refused, /user name/)
    expect { described_class.check_syntax("https:///path") }.to raise_error(described_class::Refused)
    expect { described_class.check_syntax("not a url") }.to raise_error(described_class::Refused, /not a valid URL/)
    expect { described_class.check_syntax("ftp://hooks.example.com") }.to raise_error(described_class::Refused)
  end

  it "refuses every address that is not public, however it is written or reached" do
    %w[127.0.0.1 10.1.2.3 172.16.0.9 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 ::1 fe80::1 fd00::1 ::ffff:127.0.0.1].each do |address|
      host = address.include?(":") ? "[#{address}]" : address
      expect { described_class.resolve!("https://#{host}/hook") }.to raise_error(described_class::Refused, /not a public address/), address
    end
  end

  it "refuses a name that points inside, even when only one of its addresses does, and a name that does not resolve" do
    resolving("sneaky.example.com", "93.184.216.34", "10.0.0.5")
    expect { described_class.resolve!("https://sneaky.example.com") }.to raise_error(described_class::Refused, /10.0.0.5/)
    resolving("nowhere.example.com")
    expect { described_class.resolve!("https://nowhere.example.com") }.to raise_error(described_class::Refused, /does not resolve/)
  end

  it "lets a test setup through when it is told to (and only then)" do
    Rails.configuration.x.webhooks_allow_private = true
    Rails.configuration.x.webhooks_allow_http = true
    expect(described_class.resolve!("http://127.0.0.1:9000/hook").last).to eq("127.0.0.1")
  ensure
    Rails.configuration.x.webhooks_allow_private = false
    Rails.configuration.x.webhooks_allow_http = false
  end
end
