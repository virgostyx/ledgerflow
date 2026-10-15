# B03c: the signing keys of the certificates of integrity, and the check of the books, from the command line. The private keys live in LEDGER_SIGNING_KEY_DIR, outside the
# application: nothing of them is ever printed.
namespace :integrity do
  namespace :keys do
    desc "The signing keys: identifier, status, fingerprint"
    task list: :environment do
      Ledger::SigningKeys.published.each { |key| puts "#{key['key_id']}  #{key['status'].ljust(8)}  #{key['fingerprint']}  created #{key['created_at']}" }
    end

    desc "Makes a signing key (the first one, or the next: the active one is retired). Give its fingerprint to those who will verify, by another channel."
    task generate: :environment do
      key = Ledger::SigningKeys.generate!
      puts "Key #{key.key_id} is active.\nFingerprint (SHA-256 of the public key): #{key.fingerprint}\nIts private file is in #{Ledger::SigningKeys.directory}: back it up apart from the database."
    end

    desc "The yearly rotation: the same as generate"
    task rotate: :generate

    desc "Revokes a compromised key (the file is removed, the certificates it signed say so): integrity:keys:revoke[key_id,reason]"
    task :revoke, %i[key_id reason] => :environment do |_, args|
      abort "usage: integrity:keys:revoke[key_id,reason]" if args[:key_id].blank? || args[:reason].blank?

      key = Ledger::SigningKeys.revoke!(args[:key_id], reason: args[:reason])
      puts "Key #{key.key_id} is revoked. Warn those who hold certificates it signed, and make a new key (integrity:keys:generate)."
    end
  end

  desc "Checks the integrity of the books of every company that turned the feature on: integrity:check[nightly] or integrity:check[full]"
  task :check, [ :mode ] => :environment do |_, args|
    mode = (args[:mode].presence || "nightly").to_sym
    abort "mode: nightly or full" unless %i[nightly full].include?(mode)

    broken = false
    Entity.where(active: true).find_each do |entity|
      next unless entity.feature?(:b03c)

      result = Integrity::SelfCheck.run_for(entity, mode: mode)
      broken ||= !result.intact?
      puts "[integrity] #{entity.name}: #{result.intact? ? "intact (#{result.entries_checked} entries checked)" : "#{result.findings.size} divergences"}"
      result.findings.each { |finding| puts "  - #{finding.message}" }
    end
    exit(1) if broken
  end
end
