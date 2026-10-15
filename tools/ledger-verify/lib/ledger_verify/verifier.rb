require_relative "package"

# Verifies a package of LedgerFlow without the application: standard library and OpenSSL only. Each check says what it found; the verdict is PASS when no check failed.
#
#  1. the structure: every file the manifest lists is there and has its hash, nothing else is in the archive;
#  2. the certificate: its signature (Ed25519) over its canonical form, the fingerprint of its key (and the expected one, when given);
#  3. every entry: the fingerprint recomputed from its canonical content, balanced, in the order of validation without hole;
#  4. every anchor: its hash, its link, its range, the Merkle root recomputed from the entries;
#  5. the audit chain, from the digests only, and its tie to the anchors and to the certificate;
#  6. the timestamp tokens (RFC 3161), with the certificate of the authority when given;
#  7. the totals of the certificate, recomputed;
#  8. the documents, when their files are given.
module LedgerVerify
  module Verifier
    Check = Struct.new(:code, :status, :message, keyword_init: true) # status: :pass, :fail, :skip
    HEX = /\A\h{64}\z/
    ED25519_HEADER = [ "302a300506032b6570032100" ].pack("H*").freeze
    FILES = %w[certificate.json entries.ndjson anchors.json audit_chain.ndjson accounts.json documents_manifest.json manifest.json].freeze

    class Report
      attr_reader :checks

      def initialize = @checks = []

      def add(code, status, message) = @checks << Check.new(code: code, status: status, message: message)
      def pass(code, message) = add(code, :pass, message)
      def fail(code, message) = add(code, :fail, message)
      def skip(code, message) = add(code, :skip, message)
      def failures = @checks.select { |c| c.status == :fail }
      def pass? = failures.empty?
      def verdict = pass? ? "PASS" : "FAIL"

      def to_text
        lines = @checks.map { |c| format("  %-4s %-22s %s", c.status.to_s.upcase, c.code, c.message) }
        "#{lines.join("\n")}\n\n#{verdict}#{" (#{failures.size} failed)" unless pass?}"
      end
    end

    # `data`: the package (a ZIP, or the encrypted form of one), or a certificate alone (JSON).
    def self.call(data, expected_fingerprint: nil, passphrase: nil, authority_ca: nil, documents: {})
      report = Report.new
      data = data.b
      if Package.encrypted?(data)
        return report.tap { |r| r.fail("encryption", "the package is encrypted: a passphrase is needed") } unless passphrase

        data = Package.decrypt(data, passphrase)
      end
      files = data.start_with?("PK".b) ? ZipReader.read(data) : { "certificate.json" => data.dup.force_encoding(Encoding::UTF_8) }
      run(files, report, expected_fingerprint, authority_ca, documents)
      report
    rescue ZipReader::Error, Package::WrongPassphrase => e
      report.fail("package", e.message)
      report
    end

    def self.run(files, report, expected_fingerprint, authority_ca, documents)
      whole = files.key?("manifest.json")
      check_manifest(files, report) if whole
      certificate = check_certificate(files, report, expected_fingerprint)
      unless whole
        report.skip("package", "only the certificate was given: the entries, the anchors, the audit chain and the totals are not verified")
        return
      end
      return unless certificate

      entries = check_entries(files, report)
      anchors = check_anchors(files, report, entries, certificate)
      check_audit_chain(files, report, anchors, certificate)
      check_timestamps(anchors, report, authority_ca)
      check_totals(files, report, entries, certificate)
      check_documents(files, report, documents)
    end
    private_class_method :run

    def self.json(files, name, report, code)
      JSON.parse(files.fetch(name))
    rescue KeyError
      report.fail(code, "#{name} is missing")
      nil
    rescue JSON::ParserError => e
      report.fail(code, "#{name} is not JSON: #{e.message.lines.first.strip}")
      nil
    end
    private_class_method :json

    def self.ndjson(files, name, report, code)
      return nil unless files.key?(name)

      files[name].each_line.with_index(1).filter_map do |line, number|
        next if line.strip.empty?

        JSON.parse(line)
      rescue JSON::ParserError
        report.fail(code, "#{name} line #{number} is not JSON")
        nil
      end
    end
    private_class_method :ndjson

    # 1
    def self.check_manifest(files, report)
      manifest = json(files, "manifest.json", report, "manifest") or return
      listed = Array(manifest["files"]).to_h { |file| [ file["path"], file["sha256"] ] }
      bad = false
      listed.each do |path, sha|
        if !files.key?(path) then report.fail("manifest", "#{path} is listed and missing from the archive"); bad = true
        elsif Digest::SHA256.hexdigest(files[path].b) != sha then report.fail("manifest", "#{path} does not have the hash the manifest gives"); bad = true
        end
      end
      (files.keys - listed.keys - [ "manifest.json" ]).each { |path| report.fail("manifest", "#{path} is in the archive and not in the manifest"); bad = true }
      (FILES - listed.keys - [ "manifest.json" ]).each { |path| report.fail("manifest", "#{path} is not part of the package"); bad = true }
      report.pass("manifest", "#{listed.size} files, each with the hash the manifest gives") unless bad
    end
    private_class_method :check_manifest

    # 2
    def self.check_certificate(files, report, expected_fingerprint)
      document = json(files, "certificate.json", report, "certificate") or return nil
      signature = document.delete("signature")
      key = document["public_key"].is_a?(Hash) ? document["public_key"] : {}
      raw = Base64.strict_decode64(key["public_key"].to_s) rescue "" # rubocop:disable Style/RescueModifier
      return report.tap { |r| r.fail("certificate", "the certificate has no usable public key") } && nil unless raw.bytesize == 32 && signature.is_a?(Hash)

      report.fail("key_fingerprint", "the fingerprint of the key in the certificate is not that of the key") unless Digest::SHA256.hexdigest(raw) == key["fingerprint"]
      if expected_fingerprint
        if expected_fingerprint.downcase == key["fingerprint"].to_s then report.pass("key_expected", "the key is the one expected (#{key['fingerprint'][0, 16]}...)")
        else report.fail("key_expected", "the key of the certificate (#{key['fingerprint'].to_s[0, 16]}...) is not the one expected")
        end
      else
        report.skip("key_expected", "no expected fingerprint was given: compare #{key['fingerprint']} with the one published by the issuer, by another channel")
      end
      verified = signature["key_id"] == key["key_id"] && OpenSSL::PKey.read(ED25519_HEADER + raw).verify(nil, Base64.strict_decode64(signature["value"].to_s), Canonical.generate(document))
      verified ? report.pass("signature", "the signature (Ed25519, key #{key['key_id']}) is valid over the certificate") : report.fail("signature", "the signature does not match the certificate: it was changed, or signed by another key")
      document
    rescue ArgumentError, OpenSSL::PKey::PKeyError, Canonical::Error => e
      report.fail("signature", "the certificate cannot be verified: #{e.message}")
      document
    end
    private_class_method :check_certificate

    # 3
    def self.check_entries(files, report)
      lines = ndjson(files, "entries.ndjson", report, "entries") or return []
      ok = true
      expected_seq = 0
      lines.each do |line|
        entry = line["entry"]
        id = line["id"]
        unless entry.is_a?(Hash) && line["content_hash"].to_s.match?(HEX)
          report.fail("entry", "entry #{id.inspect}: the line is not an entry with its fingerprint")
          ok = false
          next
        end
        ok &= entry_ok?(report, id, entry, line["content_hash"], expected_seq += 1)
      end
      report.pass("entries", "#{lines.size} entries: each one gives its fingerprint, is balanced, and they follow one another in the order of validation") if ok
      lines
    end
    private_class_method :check_entries

    def self.entry_ok?(report, id, entry, fingerprint, expected_seq)
      ok = true
      if Digest::SHA256.hexdigest(Canonical.generate(entry)) != fingerprint
        report.fail("entry_hash", "entry #{id} (#{entry['reference']}, place #{entry['posted_seq']}): its content does not give its fingerprint")
        ok = false
      end
      debit, credit = %w[debit credit].map { |side| Array(entry["lines"]).sum { |l| cents(l[side]) } }
      unless debit == credit
        report.fail("entry_balance", "entry #{id} (#{entry['reference']}): the debits are not the credits")
        ok = false
      end
      unless entry["posted_seq"] == expected_seq
        report.fail("entry_order", "entry #{id} (#{entry['reference']}): its place is #{entry['posted_seq'].inspect}, #{expected_seq} was expected (an entry is missing, added or moved)")
        ok = false
      end
      ok
    rescue Canonical::Error => e
      report.fail("entry_hash", "entry #{id}: cannot be written in canonical form: #{e.message}")
      false
    end
    private_class_method :entry_ok?

    # 4
    def self.check_anchors(files, report, entries, certificate)
      anchors = json(files, "anchors.json", report, "anchors") or return []
      by_seq = entries.to_h { |line| [ line.dig("entry", "posted_seq"), line["content_hash"] ] }
      ok = true
      previous = nil
      anchors.each do |anchor|
        number = anchor["number"]
        problem = anchor_problem(anchor, previous, by_seq)
        problem ? (report.fail("anchor", "anchor #{number}: #{problem}") && ok = false) : nil
        previous = anchor
      end
      last = anchors.last
      if last && certificate.dig("coverage", "anchors", "last_anchor_hash") != last["anchor_hash"]
        report.fail("anchor_certificate", "the last anchor is not the one the certificate names")
        ok = false
      end
      if last && certificate.dig("coverage", "through_seq") != last["to_seq"]
        report.fail("anchor_certificate", "the certificate covers up to place #{certificate.dig('coverage', 'through_seq')}, the last anchor up to #{last['to_seq']}")
        ok = false
      end
      report.fail("anchor", "there is no anchor") if anchors.empty?
      report.pass("anchors", "#{anchors.size} anchors: hashes, links, contiguous ranges, and the Merkle roots recomputed from the entries") if ok && anchors.any?
      anchors
    end
    private_class_method :check_anchors

    def self.anchor_problem(anchor, previous, by_seq)
      return "the number does not follow the previous anchor" unless anchor["number"] == (previous ? previous["number"] + 1 : 1)
      return "the range does not start where the previous one ended" unless anchor["from_seq"] == (previous ? previous["to_seq"] + 1 : 1)
      return "the link to the previous anchor is cut" unless anchor["previous_anchor_hash"] == previous&.fetch("anchor_hash")
      return "its hash does not follow from what it binds" unless anchor["anchor_hash"] == anchor_hash(anchor)

      range = (anchor["from_seq"]..anchor["to_seq"]).to_a
      return "it binds #{anchor['entries_count']} entries and the range holds #{range.size}" unless range.size == anchor["entries_count"]
      return "an entry of its range (place #{(range - by_seq.keys).first}) is not in the package" unless (range - by_seq.keys).empty?

      "the Merkle root of its entries is not the recorded root" unless Merkle.root_of_hex(range.map { |seq| by_seq[seq] }) == anchor["merkle_root"]
    end
    private_class_method :anchor_problem

    def self.anchor_hash(anchor)
      Digest::SHA256.hexdigest(Canonical.generate("previous" => anchor["previous_anchor_hash"], "from_seq" => anchor["from_seq"], "to_seq" => anchor["to_seq"], "root" => anchor["merkle_root"],
                                                  "count" => anchor["entries_count"], "audit_head" => anchor["audit_head"], "audit_length" => anchor["audit_length"], "anchored_at" => anchor["anchored_at"]))
    end
    private_class_method :anchor_hash

    # 5
    def self.check_audit_chain(files, report, anchors, certificate)
      rows = ndjson(files, "audit_chain.ndjson", report, "audit_chain") or return
      result = AuditChain.verify(rows)
      if result.ok?
        report.pass("audit_chain", "#{result.checked} events, linked#{" (#{result.linked_only} of the first version only by their links)" if result.linked_only.positive?}")
      else
        return report.fail("audit_chain", "event #{result.broken_id}: #{result.reason}")
      end
      anchors.each do |anchor|
        held = anchor["audit_length"].to_i.zero? ? anchor["audit_head"].nil? : rows[anchor["audit_length"] - 1]&.fetch("hash") == anchor["audit_head"]
        report.fail("audit_anchor", "anchor #{anchor['number']}: the head of the audit chain it binds is not in the chain") unless held
      end
      head = certificate.dig("audit_chain", "head")
      report.fail("audit_certificate", "the head of the audit chain in the certificate is not in the chain") if head && rows.none? { |row| row["hash"] == head }
    end
    private_class_method :check_audit_chain

    # 6
    def self.check_timestamps(anchors, report, authority_ca)
      tokens = anchors.select { |anchor| anchor["timestamp_token"] }
      return report.skip("timestamps", "no external timestamp: the proof rests on the signing key of the issuer alone") if tokens.empty?
      return report.skip("timestamps", "#{tokens.size} timestamp tokens were not verified: give the certificate of the authority (--authority-ca)") unless authority_ca

      tokens.each do |anchor|
        ok, detail = verify_token(anchor["timestamp_token"], anchor["anchor_hash"], authority_ca)
        ok ? report.pass("timestamp", "anchor #{anchor['number']}: the timestamp token is valid") : report.fail("timestamp", "anchor #{anchor['number']}: #{detail}")
      end
    end
    private_class_method :check_timestamps

    def self.verify_token(token, anchor_hash, authority_ca)
      Tempfile.create([ "token", ".tsr" ]) do |file|
        file.binmode.write(Base64.decode64(token))
        file.flush
        Tempfile.create([ "ca", ".pem" ]) do |ca|
          ca.write(authority_ca)
          ca.flush
          output, status = Open3.capture2e("openssl", "ts", "-verify", "-in", file.path, "-digest", anchor_hash, "-sha256", "-CAfile", ca.path)
          [ status.success?, "the token does not verify (#{output.lines.last.to_s.strip})" ]
        end
      end
    end
    private_class_method :verify_token

    # 7
    def self.check_totals(files, report, entries, certificate)
      scope = certificate.dig("scope", "fiscal_year_id")
      lines = entries.select { |l| scope.nil? || l.dig("entry", "fiscal_year_id") == scope }.flat_map { |l| l.dig("entry", "lines") || [] }
      entry_count = entries.count { |l| scope.nil? || l.dig("entry", "fiscal_year_id") == scope }
      report.fail("coverage", "the certificate says #{certificate.dig('coverage', 'entries')} entries, the package holds #{entry_count}") unless certificate.dig("coverage", "entries") == entry_count
      report.fail("coverage", "the certificate says #{certificate.dig('coverage', 'lines')} lines, the package holds #{lines.size}") if certificate.dig("coverage", "lines") && certificate.dig("coverage", "lines") != lines.size
      totals = certificate["totals"]
      return report.skip("totals", "the certificate gives no totals (minimal level)") unless totals

      debit, credit = %w[debit credit].map { |side| lines.sum { |l| cents(l[side]) } }
      if money(debit) == totals["debit"] && money(credit) == totals["credit"] && debit == credit
        report.pass("totals", "total debit #{totals['debit']} = total credit #{totals['credit']}, recomputed")
      else
        report.fail("totals", "the totals of the certificate (#{totals['debit']} / #{totals['credit']}) are not those of the entries (#{money(debit)} / #{money(credit)})")
      end
      check_classes(files, report, lines, totals)
    end
    private_class_method :check_totals

    def self.check_classes(files, report, lines, totals)
      accounts = files.key?("accounts.json") ? JSON.parse(files["accounts.json"]) : nil
      return report.skip("totals_by_class", "no accounts.json: the summary by class is not verified") unless accounts

      classes = accounts.to_h { |a| [ a["id"], a["code"].to_s[0] ] }
      computed = lines.group_by { |l| classes[l["account_id"]] }.transform_values { |ls| { "debit" => money(ls.sum { |l| cents(l["debit"]) }), "credit" => money(ls.sum { |l| cents(l["credit"]) }) } }
      if computed == totals["by_class"]
        report.pass("totals_by_class", "the summary by class of accounts is that of the entries (the class of an account is taken from accounts.json, which the certificate does not attest)")
      else
        report.fail("totals_by_class", "the summary by class of the certificate is not that of the entries")
      end
    end
    private_class_method :check_classes

    # 8
    def self.check_documents(files, report, documents)
      manifest = files.key?("documents_manifest.json") ? JSON.parse(files["documents_manifest.json"]) : []
      return report.skip("documents", "no document files were given: #{manifest.size} documents are listed with their fingerprint") if documents.empty?

      known = manifest.to_h { |d| [ d["sha256"], d ] }
      documents.each do |name, content|
        known.key?(Digest::SHA256.hexdigest(content.b)) ? report.pass("document", "#{name} is the document the package lists") : report.fail("document", "#{name} is not a document the package lists (changed, or not part of it)")
      end
    end
    private_class_method :check_documents

    # "123.45" -> 12345, "-0.50" -> -50: amounts are decimal strings with two decimals, summed as integers.
    def self.cents(text)
      whole, fraction = text.to_s.split(".")
      sign = whole.start_with?("-") ? -1 : 1
      sign * (whole.delete("-").to_i * 100 + fraction.to_s.ljust(2, "0")[0, 2].to_i)
    end
    private_class_method :cents

    def self.money(cents) = format("%s%d.%02d", cents.negative? ? "-" : "", cents.abs / 100, cents.abs % 100)
    private_class_method :money
  end
end
