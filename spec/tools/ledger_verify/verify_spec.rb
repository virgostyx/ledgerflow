require "rails_helper"
require Rails.root.join("tools/ledger-verify/lib/ledger_verify")

# B03c critères 3 et 4, and §13 "Vérification indépendante": `ledger-verify` says PASS on an intact package, without the application, and FAIL on each kind of alteration, naming
# the entry or the anchor at fault. The package is built by the application; it is read by the tool alone (standard library and OpenSSL).
RSpec.describe LedgerVerify::Verifier do
  include_context "with_open_fiscal_year"
  include_context "with signing keys directory"

  let(:journal) { create(:journal, :purchase) }
  let(:user) { create(:user).tap { |u| create(:user_entity, :accountant, user: u, entity: entity) } }
  let!(:expense) { create(:account, code: "604000", account_type: :expense, normal_balance: :debit, account_class: 6) }
  let!(:payable) { create(:account, code: "440000", account_type: :liability, normal_balance: :credit, account_class: 4) }

  before do
    entity.update!(features: entity.features.merge("b03c" => true))
    Ledger::SigningKeys.generate!
  end

  def post_entry(amount)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year, entry_date: fiscal_year.start_date + 10, reference: nil)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, journal_entry: entry, account: expense, debit: amount, credit: 0, label: "Services")
    create(:journal_entry_line, journal_entry: entry, account: payable, debit: 0, credit: amount, label: "Acme")
    Current.set(user: user) { Accounting::PostJournalEntry.call!(entry: entry) }
    entry.reload
  end

  let(:package) do
    2.times { |i| post_entry(10 + i) }
    Ledger::Anchoring.call(kind: "nightly")
    3.times { |i| post_entry(100 + i) }
    Ledger::Anchoring.call(kind: "nightly")
    post_entry(7)
    certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "full", recipient: "Auditor")[:certificate]
    Integrity::BuildPackage.call(certificate: certificate).data
  end

  def files = Accounting::Zipper.read(package)

  # The package with one file changed (and its line in the manifest kept as it was, unless `manifest: true` says the forger also fixed the manifest).
  def altered(manifest: false, &block)
    contents = files
    block.call(contents)
    if manifest
      list = JSON.parse(contents["manifest.json"])
      list["files"] = list["files"].filter_map { |f| contents.key?(f["path"]) ? f.merge("sha256" => Digest::SHA256.hexdigest(contents[f["path"]].b)) : nil }
      contents["manifest.json"] = JSON.generate(list)
    end
    Accounting::Zipper.build(contents.to_a)
  end

  def verify(data, **opts) = described_class.call(data, **opts)

  def edit_ndjson(contents, name)
    rows = contents[name].each_line.map { |l| JSON.parse(l) }
    yield rows
    contents[name] = rows.map { |r| "#{LedgerVerify::Canonical.generate(r)}\n" }.join
  end

  it "says PASS on an intact package, every check passed" do
    report = verify(package)

    expect(report.failures).to be_empty
    expect(report).to be_pass
    expect(report.verdict).to eq("PASS")
    expect(report.checks.map(&:code)).to include("manifest", "signature", "entries", "anchors", "audit_chain", "totals", "totals_by_class")
    expect(report.checks.find { |c| c.code == "timestamps" }.message).to include("no external timestamp")
  end

  it "checks the key against the fingerprint expected by another channel" do
    fingerprint = Ledger::SigningKey.find_by!(status: "active").fingerprint

    expect(verify(package, expected_fingerprint: fingerprint)).to be_pass
    wrong = verify(package, expected_fingerprint: "0" * 64)
    expect(wrong).not_to be_pass
    expect(wrong.failures.map(&:code)).to include("key_expected")
  end

  describe "an alteration, whatever it is, fails, with the entry or the anchor named" do
    # [what is done, the checks that must fail]. The forger fixes the manifest each time (as he would): each layer has to catch what concerns it.
    {
      "an amount changed in an entry" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows[2]["entry"]["lines"][0]["debit"] = "999.00" } }, %w[entry_hash] ],
      "a reference changed in an entry" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows[1]["entry"]["reference"] = "FORGED" } }, %w[entry_hash] ],
      "a label changed in a line" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows[3]["entry"]["lines"][1]["label"] = "Other" } }, %w[entry_hash] ],
      "an entry removed" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows.delete_at(2) } }, %w[entry_order anchor] ],
      "an entry added" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows << rows.last.merge("id" => 99_999) } }, %w[entry_order] ],
      "two entries swapped" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows[1], rows[2] = rows[2], rows[1] } }, %w[entry_order] ],
      "the fingerprint of an entry changed" => [ ->(c, _) { edit_ndjson(c, "entries.ndjson") { |rows| rows[0]["content_hash"] = "a" * 64 } }, %w[entry_hash anchor] ],
      "an entry made unbalanced, with its fingerprint recomputed" => [ lambda { |c, _|
        edit_ndjson(c, "entries.ndjson") do |rows|
          rows[4]["entry"]["lines"][0]["debit"] = "500.00"
          rows[4]["content_hash"] = Digest::SHA256.hexdigest(LedgerVerify::Canonical.generate(rows[4]["entry"]))
        end
      }, %w[entry_balance anchor] ],
      "the Merkle root of an anchor changed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a[0]["merkle_root"] = "b" * 64; c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the hash of an anchor changed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a[1]["anchor_hash"] = "c" * 64; c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "an anchor of the middle removed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a.delete_at(1); c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the last anchor removed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a.pop; c["anchors.json"] = JSON.generate(a) }, %w[anchor_certificate] ],
      "the first anchor removed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a.delete_at(0); c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the count of an anchor changed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a[0]["entries_count"] = 9; c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the link of an anchor cut" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a[1]["previous_anchor_hash"] = "d" * 64; c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the date of an anchor changed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a[0]["anchored_at"] = "2020-01-01T00:00:00.000000Z"; c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the head of the audit chain bound by an anchor changed" => [ ->(c, _) { a = JSON.parse(c["anchors.json"]); a[0]["audit_head"] = "9" * 64; c["anchors.json"] = JSON.generate(a) }, %w[anchor] ],
      "the digest of an audit event changed" => [ ->(c, _) { edit_ndjson(c, "audit_chain.ndjson") { |rows| rows.reverse.find { |r| r["version"] == 2 }["content_digest"] = "e" * 64 } }, %w[audit_chain] ],
      "an audit event removed" => [ ->(c, _) { edit_ndjson(c, "audit_chain.ndjson") { |rows| rows.delete_at(rows.size / 2) } }, %w[audit_chain] ],
      "the hash of an audit event changed" => [ ->(c, _) { edit_ndjson(c, "audit_chain.ndjson") { |rows| rows[rows.size - 2]["hash"] = "f" * 64 } }, %w[audit_chain] ],
      "the metadata of an audit event changed" => [ ->(c, _) { edit_ndjson(c, "audit_chain.ndjson") { |rows| rows.last["metadata"]["action"] = "nothing_happened" } }, %w[audit_chain] ],
      "the totals of the certificate changed" => [ ->(c, _) { d = JSON.parse(c["certificate.json"]); d["totals"]["debit"] = "1.00"; c["certificate.json"] = JSON.generate(d) }, %w[signature] ],
      "the company named in the certificate changed" => [ ->(c, _) { d = JSON.parse(c["certificate.json"]); d["company"]["name"] = "Someone else"; c["certificate.json"] = JSON.generate(d) }, %w[signature] ],
      "a reservation taken out of the certificate" => [ ->(c, _) { d = JSON.parse(c["certificate.json"]); d["reservations"] = []; c["certificate.json"] = JSON.generate(d) }, %w[signature] ],
      "the range covered by the certificate changed" => [ ->(c, _) { d = JSON.parse(c["certificate.json"]); d["coverage"]["through_seq"] = 3; c["certificate.json"] = JSON.generate(d) }, %w[signature anchor_certificate] ],
      "the signature of another message put in" => [ ->(c, _) { d = JSON.parse(c["certificate.json"]); d["signature"]["value"] = Base64.strict_encode64("x" * 64); c["certificate.json"] = JSON.generate(d) }, %w[signature] ],
      "a file of the package removed" => [ ->(c, _) { c.delete("anchors.json") }, %w[manifest] ],
      "a file added to the package" => [ ->(c, _) { c["extra.txt"] = "hello" }, %w[manifest] ],
      "the class of an account changed in accounts.json" => [ ->(c, _) { a = JSON.parse(c["accounts.json"]); a[0]["code"] = "9" + a[0]["code"][1..]; c["accounts.json"] = JSON.generate(a) }, %w[totals_by_class] ]
    }.each do |name, (change, codes)|
      it "fails when #{name}, in the check that concerns it, even if the manifest was made again" do
        report = verify(altered(manifest: true) { |c| instance_exec(c, nil, &change) })

        expect(report).not_to be_pass, "the alteration was not detected"
        expect(report.failures.map(&:code) & codes).not_to be_empty, "failed in #{report.failures.map(&:code).uniq}, not in #{codes}"
      end
    end

    it "fails when a file was changed and the manifest not" do
      report = verify(altered { |c| c["accounts.json"] = "[]" })

      expect(report.failures.map(&:code)).to include("manifest")
    end

    it "names the entry whose content was changed" do
      victim = JSON.parse(files["entries.ndjson"].lines[2])
      report = verify(altered(manifest: true) { |c| edit_ndjson(c, "entries.ndjson") { |rows| rows[2]["entry"]["lines"][0]["debit"] = "999.00" } })

      expect(report.failures.map(&:message).join("\n")).to include("entry #{victim['id']}")
      expect(report.failures.map(&:code)).to include("entry_hash")
    end

    it "names the anchor whose root no longer follows from the entries, even when the manifest was fixed by the forger" do
      report = verify(altered(manifest: true) { |c| edit_ndjson(c, "entries.ndjson") { |rows| rows[3]["content_hash"] = "a" * 64 } })

      expect(report.failures.map(&:message).join("\n")).to match(/anchor 2.*Merkle root|entry \d+/)
    end

    it "names the anchor that was altered (its hash, its link, its root)" do
      report = verify(altered(manifest: true) { |c| a = JSON.parse(c["anchors.json"]); a[1]["merkle_root"] = "b" * 64; c["anchors.json"] = JSON.generate(a) })

      expect(report.failures.map(&:message).join("\n")).to include("anchor 2")
    end

    it "fails on a signature made with another key, when the fingerprint expected is the real one (the forger put his own key in)" do
      real = Ledger::SigningKey.find_by!(status: "active").fingerprint
      forged = altered(manifest: true) do |c|
        attacker = OpenSSL::PKey.generate_key("ED25519")
        d = JSON.parse(c["certificate.json"])
        d.delete("signature")
        raw = attacker.raw_public_key
        d["public_key"] = { "key_id" => "attacker", "algorithm" => "Ed25519", "public_key" => Base64.strict_encode64(raw), "fingerprint" => Digest::SHA256.hexdigest(raw) }
        d["signature"] = { "key_id" => "attacker", "algorithm" => "Ed25519", "value" => Base64.strict_encode64(attacker.sign(nil, LedgerVerify::Canonical.generate(d.except("signature")))) }
        c["certificate.json"] = JSON.generate(d)
      end

      expect(verify(forged)).to be_pass # signed with the key it carries: only the fingerprint expected by another channel says it is not the issuer's
      expect(verify(forged, expected_fingerprint: real)).not_to be_pass
    end

    it "fails on what is not a package" do
      expect(verify("not a package at all")).not_to be_pass
      expect(verify(package.byteslice(0, 300))).not_to be_pass
    end

    it "does not trust an archive whose names climb out of it" do
      evil = Accounting::Zipper.build([ [ "../escape.txt", "x" ], [ "manifest.json", "{}" ] ])

      expect(verify(evil)).not_to be_pass
    end
  end

  describe "with the timestamps of an authority (RFC 3161)" do
    include_context "with a timestamp authority"

    let(:stamped) do
      entity.update!(timestamp_authority_url: "https://tsa.example.test/tsr", timestamp_authority_ca: authority.ca_pem)
      allow(Ledger::Timestamping).to receive(:default_transport).and_return(authority.transport)
      post_entry(5)
      Ledger::Anchoring.call(kind: "nightly").then { |a| Ledger::Timestamping.call(a, transport: authority.transport) }
      post_entry(6)
      certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "full")[:certificate]
      Integrity::BuildPackage.call(certificate: certificate).data
    end

    it "verifies every token against the certificate of the authority, with an outside tool (openssl ts)" do
      report = verify(stamped, authority_ca: authority.ca_pem)

      expect(report).to be_pass
      expect(report.checks.select { |c| c.code == "timestamp" }.map(&:status)).to eq(%i[pass pass])
    end

    it "does not verify them without the certificate of the authority, and says so" do
      report = verify(stamped)

      expect(report).to be_pass
      expect(report.checks.find { |c| c.code == "timestamps" }.message).to include("--authority-ca")
    end

    it "fails when the tokens do not come from the authority given, or belong to another anchor" do
      expect(verify(stamped, authority_ca: TestTimestampAuthority.new.ca_pem)).not_to be_pass

      swapped = Accounting::Zipper.read(stamped).tap do |c|
        a = JSON.parse(c["anchors.json"])
        a[0]["timestamp_token"], a[1]["timestamp_token"] = a[1]["timestamp_token"], a[0]["timestamp_token"]
        c["anchors.json"] = JSON.generate(a)
        list = JSON.parse(c["manifest.json"])
        list["files"].each { |f| f["sha256"] = Digest::SHA256.hexdigest(c[f["path"]].b) if f["path"] == "anchors.json" }
        c["manifest.json"] = JSON.generate(list)
      end
      expect(verify(Accounting::Zipper.build(swapped.to_a), authority_ca: authority.ca_pem)).not_to be_pass
    end
  end

  describe "a package protected by a passphrase" do
    it "is opened with it, and refused without, or with another" do
      certificate = nil
      post_entry(5)
      certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "full")[:certificate]
      sealed = Integrity::BuildPackage.call(certificate: certificate, passphrase: "correct horse")

      expect(sealed.encrypted).to be(true)
      expect(sealed.filename).to end_with(".zip.enc")
      expect(verify(sealed.data, passphrase: "correct horse")).to be_pass
      expect(verify(sealed.data)).not_to be_pass
      expect(verify(sealed.data, passphrase: "wrong")).not_to be_pass
      expect(sealed.data).not_to include("ledgerflow-integrity-certificate")
    end
  end

  describe "the certificate alone (levels minimal and standard)" do
    it "verifies the signature and says that the rest is not verifiable" do
      post_entry(5)
      certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "standard")[:certificate]

      report = verify(JSON.generate(certificate.to_document))

      expect(report).to be_pass
      expect(report.checks.find { |c| c.code == "package" }.status).to eq(:skip)
      tampered = JSON.parse(JSON.generate(certificate.to_document)).tap { |d| d["totals"]["debit"] = "1.00" }
      expect(verify(JSON.generate(tampered))).not_to be_pass
    end
  end

  describe "the command, without the application" do
    let(:bin) { Rails.root.join("tools/ledger-verify/bin/ledger-verify").to_s }
    let(:work) { Dir.mktmpdir("pkg") }

    after { FileUtils.rm_rf(work) }

    # A bare Ruby: no bundler, no gems, no environment of the application, nothing but the standard library and OpenSSL.
    def run_tool(*args) = Open3.capture3({}, RbConfig.ruby, "--disable-gems", bin, *args, unsetenv_others: true, chdir: work)

    it "says PASS and exits 0 on an intact package, FAIL and exits 1 on an altered one, 2 when it is badly called" do
      File.binwrite(File.join(work, "good.zip"), package)
      File.binwrite(File.join(work, "bad.zip"), altered(manifest: true) { |c| edit_ndjson(c, "entries.ndjson") { |rows| rows[1]["entry"]["reference"] = "FORGED" } })

      out, err, status = run_tool(File.join(work, "good.zip"))
      expect([ status.exitstatus, out.lines.last.strip, err ]).to eq([ 0, "PASS", "" ])

      out, _err, status = run_tool(File.join(work, "bad.zip"))
      expect(status.exitstatus).to eq(1)
      expect(out).to include("FAIL").and include("entry_hash")

      _out, _err, status = run_tool
      expect(status.exitstatus).to eq(2)
    end

    it "gives the verdict as JSON, checks the expected fingerprint, opens an encrypted package with a passphrase from the environment" do
      File.binwrite(File.join(work, "good.zip"), package)
      fingerprint = Ledger::SigningKey.find_by!(status: "active").fingerprint

      out, = run_tool(File.join(work, "good.zip"), "--json", "--fingerprint", fingerprint)
      expect(JSON.parse(out)).to include("verdict" => "PASS")
      _, _, status = run_tool(File.join(work, "good.zip"), "--fingerprint", "0" * 64)
      expect(status.exitstatus).to eq(1)

      sealed = LedgerVerify::Package.encrypt(package, "open sesame")
      File.binwrite(File.join(work, "sealed.zip.enc"), sealed)
      File.write(File.join(work, "pass.txt"), "open sesame\n")
      _, _, status = run_tool(File.join(work, "sealed.zip.enc"), "--passphrase-file", File.join(work, "pass.txt"))
      expect(status.exitstatus).to eq(0)
      _, _, status = run_tool(File.join(work, "sealed.zip.enc"))
      expect(status.exitstatus).to eq(1)
    end
  end

  it "builds the same package twice from the same certificate (determinism)" do
    certificate = nil
    post_entry(5)
    certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "full")[:certificate]

    expect(Integrity::BuildPackage.call(certificate: certificate).data).to eq(Integrity::BuildPackage.call(certificate: certificate).data)
  end

  it "refuses to build a package for a level below full" do
    post_entry(5)
    certificate = Integrity::IssueCertificate.call(user: user, recent_second_factor: true, disclosure: "standard")[:certificate]

    expect { Integrity::BuildPackage.call(certificate: certificate) }.to raise_error(ArgumentError, /full/)
  end
end
