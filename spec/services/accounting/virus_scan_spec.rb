require "rails_helper"

# The point of entry for an antivirus (F03): off unless configured; a configured scanner that is down refuses the file.
RSpec.describe Accounting::VirusScan do
  EICAR = 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*'.freeze

  around do |example|
    previous = Rails.configuration.x.document_virus_scan
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  ensure
    Rails.configuration.x.document_virus_scan = previous
  end

  # A stand-in for clamscan: reads the file on its standard input, exits 1 (infected) on the EICAR test string, 0 otherwise.
  def fake_scanner(exit_when_infected: 1, exit_otherwise: 0)
    path = File.join(@dir, "scanner.sh")
    File.write(path, "#!/bin/sh\nif grep -q EICAR-STANDARD; then exit #{exit_when_infected}; fi\nexit #{exit_otherwise}\n")
    File.chmod(0o755, path)
    path
  end

  def configure(command, fail_open: false) = Rails.configuration.x.document_virus_scan = { command: command, fail_open: fail_open }

  it "does nothing when no scanner is configured" do
    Rails.configuration.x.document_virus_scan = nil

    expect(described_class.call("anything")).to eq(:clean)
  end

  it "passes a clean file" do
    configure([ fake_scanner ])

    expect(described_class.call("harmless text")).to eq(:clean)
  end

  it "recognises an infected file" do
    configure([ fake_scanner ])

    expect(described_class.call(EICAR)).to eq(:infected)
  end

  it "refuses to say a file is clean when the scanner fails (exit code other than 0 and 1)" do
    configure([ fake_scanner(exit_otherwise: 2) ])

    expect(described_class.call("harmless text")).to eq(:unavailable)
  end

  it "refuses when the scanner is not installed" do
    configure([ "no-such-scanner" ])

    expect(described_class.call("harmless text")).to eq(:unavailable)
  end

  it "can be told to let files through when the scanner is down (never when it finds a virus)" do
    configure([ "no-such-scanner" ], fail_open: true)
    expect(described_class.call("harmless text")).to eq(:clean)

    configure([ fake_scanner ], fail_open: true)
    expect(described_class.call(EICAR)).to eq(:infected)
  end

  it "is configured from the environment" do
    expect(Rails.application.config.x).to respond_to(:document_virus_scan)
  end
end
