# F01: who may do what, by role held in the entity (UserEntity#role). The only place rights are declared;
# policies ask `can?(permission)` and never test a role themselves. Follows the capability table of
# docs/dev/features/spec.md §4 (owner = admin, reader = manager, external auditor = auditor).
module Permissions
  EVERYONE = %i[admin accountant assistant manager auditor].freeze

  MATRIX = {
    "records.view"           => EVERYONE,
    "records.list"           => EVERYONE,
    "records.write"          => %i[admin accountant assistant],
    "records.delete"         => %i[admin],
    "entries.post"           => %i[admin accountant],
    "entries.reverse"        => %i[admin accountant],
    "invoices.issue"         => %i[admin accountant],
    "reconciliations.manage" => %i[admin accountant assistant],
    "reconciliations.cross_partner"      => %i[admin accountant], # letter lines of different partners (a correction), with a reason
    "reconciliations.unreconcile_locked" => %i[admin],           # undo a lettering whose lines are in a locked period
    "entry_templates.manage" => %i[admin accountant],  # entry templates (F07)
    "recurring.manage"       => %i[admin accountant],  # recurring entries: create, pause, resume (F07)
    "recurring.approve_post" => %i[admin],             # lets a recurring entry post by itself (F07)
    "peppol.review"          => %i[admin accountant assistant], # received invoices: look, work on again, pick the supplier, dismiss (F06)
    "peppol.send"            => %i[admin accountant],           # send an invoice through Peppol, send it again
    "peppol.configure"       => %i[admin accountant],           # Access Point, credentials, VAT category mappings, account proposals
    "tasks.manage"           => %i[admin accountant assistant], # create, assign, change and close tasks (F08)
    "comments.write"         => %i[admin accountant assistant], # comment on what one can see (F08)
    "vat.file"               => %i[admin accountant],
    "payments.manage"        => %i[admin accountant],
    "dunning.send"           => %i[admin accountant],
    "periods.lock"           => %i[admin accountant],
    "periods.unlock"         => %i[admin],
    "users.manage"           => %i[admin],
    "settings.manage"        => %i[admin accountant],
    "closing.adjust"         => %i[admin accountant],
    "fiscal_years.manage"    => %i[admin],
    "documents.view"         => EVERYONE,
    "documents.upload"       => %i[admin accountant assistant],
    "documents.link"         => %i[admin accountant assistant],
    "documents.archive"      => %i[admin accountant],
    "documents.delete_expired" => %i[admin],
    "bank.import"            => %i[admin accountant],
    "bank.match"             => %i[admin accountant assistant],
    "reports.view"           => EVERYONE,
    "reports.export"         => %i[admin accountant assistant],
    # the read-only roles export only when the entity allows it (Entity#read_only_export), see ApplicationPolicy#can_export?
    "reports.export_readonly" => %i[manager auditor],
    "audit.view"             => %i[admin accountant auditor]
  }.freeze

  # The roles that can validate, unlock or administer: they must sign in with a second factor.
  SENSITIVE = %w[entries.post periods.unlock users.manage].freeze

  # An unknown permission raises: a typo must never turn into a silent denial (or worse, a grant).
  def self.allowed?(role, permission) = MATRIX.fetch(permission.to_s).include?(role&.to_sym)

  def self.sensitive?(role) = SENSITIVE.any? { |permission| allowed?(role, permission) }
end
