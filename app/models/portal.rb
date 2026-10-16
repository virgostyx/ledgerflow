# B02a: the client portal. Its tables are portal_* (and the portal_companies view); see Portal::BaseController.
module Portal
  ROLES = %w[director collaborator reader].freeze

  # What a grant can hold. A right exists only if the grant lists it: nothing is allowed by default. The role only suggests a starting set.
  CAPABILITIES = %w[publications.view dashboard.view documents.upload questions.answer bank_lines.view accounts.approve access.request messages.use].freeze
  ROLE_CAPABILITIES = {
    "director"     => CAPABILITIES,
    "collaborator" => %w[publications.view dashboard.view documents.upload questions.answer bank_lines.view messages.use],
    "reader"       => []
  }.freeze

  INVITATION_VALIDITY = 7.days
  IDLE_TIMEOUT = 30.minutes
  SESSION_MAXIMUM = 12.hours
  RECENT_SECOND_FACTOR = 5.minutes

  def self.table_name_prefix = "portal_"

  def self.restricted_database? = Rails.configuration.x.portal_database_restricted

  # Where the portal is, for the links in e-mails.
  def self.url_options
    { host: Rails.configuration.x.portal_host, protocol: (Rails.env.production? ? "https" : "http"), port: (Rails.env.development? ? 3000 : nil) }.compact
  end
end
