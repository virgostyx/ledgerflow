# F01: who may do what, by role held in the entity (UserEntity#role). The only place rights are declared;
# policies ask `can?(permission)` and never test a role themselves.
module Permissions
  MATRIX = {
    "records.view"           => %i[admin accountant manager auditor],
    "records.list"           => %i[admin accountant manager],
    "records.write"          => %i[admin accountant],
    "records.delete"         => %i[admin],
    "entries.post"           => %i[admin accountant],
    "entries.reverse"        => %i[admin accountant],
    "invoices.issue"         => %i[admin accountant],
    "reconciliations.manage" => %i[admin accountant],
    "vat.file"               => %i[admin accountant],
    "payments.manage"        => %i[admin accountant],
    "dunning.send"           => %i[admin accountant],
    "periods.lock"           => %i[admin accountant],
    "periods.unlock"         => %i[admin],
    "users.manage"           => %i[admin],
    "settings.manage"        => %i[admin accountant],
    "closing.adjust"         => %i[admin accountant],
    "fiscal_years.manage"    => %i[admin],
    "reports.view"           => %i[admin accountant manager],
    "audit.view"             => %i[admin accountant manager auditor]
  }.freeze

  # An unknown permission raises: a typo must never turn into a silent denial (or worse, a grant).
  def self.allowed?(role, permission) = MATRIX.fetch(permission.to_s).include?(role&.to_sym)
end
