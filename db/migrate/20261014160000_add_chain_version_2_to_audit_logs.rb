# B03c, evolution of R18: version 2 of the audit chain keeps the digest of the content of each event (`content_digest`) and links the events by
# SHA-256(previous hash || content digest || metadata), so that a third party can verify the chain without reading what the events say.
#
# No existing event is touched (the table cannot be changed, and it must not be): the events written so far stay version 1 (`chain_version` NULL), the first one written after
# this migration puts a switch event on the head of version 1 and goes on in version 2.
class AddChainVersion2ToAuditLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :accounting_audit_logs, :content_digest, :string, limit: 64
    add_column :accounting_audit_logs, :chain_version, :integer, limit: 2
    add_check_constraint :accounting_audit_logs, "chain_version IS NULL OR chain_version = 2", name: "chk_audit_logs_chain_version"
    add_check_constraint :accounting_audit_logs, "COALESCE(chain_version = 2, false) = (content_digest IS NOT NULL)", name: "chk_audit_logs_content_digest"
  end
end
