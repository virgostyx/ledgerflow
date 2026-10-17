# B03c: what a certificate says of the software that issued it: its revision, and the fingerprint of the files that make the integrity (the canonical form, the fingerprints, the
# anchors, the certificates, the verifier). A change to any of them changes the hash.
module Integrity::SoftwareManifest
  FILES = %w[app/services/ledger app/services/integrity app/models/ledger app/models/integrity_certificate.rb tools/ledger-verify/lib].freeze

  def self.call
    { "revision" => revision, "manifest_hash" => manifest_hash }
  end

  def self.revision = ENV["GIT_REVISION"].presence || ENV["KAMAL_VERSION"].presence || `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown"

  def self.manifest_hash
    files = FILES.flat_map { |path| File.directory?(Rails.root.join(path)) ? Dir[Rails.root.join(path, "**/*.rb").to_s] : [ Rails.root.join(path).to_s ] }.sort
    Digest::SHA256.hexdigest(files.map { |file| "#{Pathname(file).relative_path_from(Rails.root)}:#{Digest::SHA256.file(file).hexdigest}" }.join("\n"))
  end
end
