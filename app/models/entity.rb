class Entity < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :user_entities, dependent: :destroy
  has_many :users, through: :user_entities
  belongs_to :organization, optional: true # F12a: the firm or the group this entity belongs to
  belongs_to :responsible, class_name: "User", optional: true # F12a: the person in charge of the dossier
  has_many :health_snapshots, class_name: "DossierHealthSnapshot", dependent: :delete_all

  enum :vat_filing_frequency, { monthly: 0, quarterly: 1 }
  enum :vat_regime,           { normal: 0, franchise: 1 }
  enum :vat_scheme,           { normal: 0, mixed: 1 }, prefix: :vat_scheme
  # The Peppol Access Point of this entity (one adapter per provider, see Peppol::AccessPoint); nil = not set up.
  enum :peppol_access_point,  { simulator: 0, digiteal: 1, b2brouter: 2 }, prefix: :peppol_ap

  # Multi-currency rules (F11): which rate, on which date, how an unrealized exchange difference is treated.
  enum :rate_policy,        { daily: 0, monthly_average: 1, manual: 2 }, prefix: :rates
  enum :rate_date_basis,    { document_date: 0, accounting_date: 1 }
  enum :fx_unrealized_loss, { expense: 0, ignore: 1 }, prefix: :unrealized_loss
  enum :fx_unrealized_gain, { defer: 0, recognize: 1, ignore: 2 }, prefix: :unrealized_gain

  serialize :peppol_credentials, type: Hash, coder: JSON
  encrypts  :peppol_credentials
  has_secure_token :peppol_webhook_token
  # The secret part of the address that receives this entity's documents by e-mail (F03).
  has_secure_token :documents_mail_token
  normalizes :peppol_participant_id, with: ->(id) { id.strip.presence }

  # A blank number must be NULL: the unique index on vat_number only skips NULLs.
  normalizes :vat_number, with: ->(number) { number.strip.presence }

  validates :name,       presence: true
  validates :legal_name, presence: true
  validates :country,    presence: true
  validates :vat_number, uniqueness: true, allow_blank: true
  validates :rate_alert_pct, numericality: { greater_than_or_equal_to: 0 }
  validates :fx_loss_account_code, :fx_gain_account_code, presence: true
  validate  :rate_fallback_currencies_are_currencies
  validate  :vat_number_format
  validates :peppol_participant_id, uniqueness: true, allow_nil: true # routes the documents received to their entity
  validate  :peppol_participant_id_format, :simulator_allowed, :peppol_credentials_complete

  scope :active, -> { where(active: true) }

  def documents_email = "documents+#{documents_mail_token}@#{Rails.configuration.x.documents_mail_domain}"

  # The features of docs/dev/features/spec.md that are built, each shipped behind a per-entity flag. A function adds its
  # key here when it ships.
  FEATURES = %w[f01 f02 f03 f08 f09 f10 f11 f12 f13 agent b01a b01b b02a b03a b03b b03c].freeze
  FEATURE_LABELS = {
    "f01" => [ "Roles, period locks and users", "Turns on the Periods and Users and roles screens and the four-eyes option. The safeguards (a locked period refuses entries, the last owner stays) stay active either way." ],
    "f02" => [ "Bank statements (CODA)", "Turns on the import of CODA bank statements and the automatic reconciliation of their lines." ],
    "f03" => [ "Documents", "Turns on the document inbox: upload, view, link to entries and archive supporting documents." ],
    "f08" => [ "Tasks and comments", "Turns on tasks and comment threads on entries, ledger lines, accounts, partners, documents and bank lines, with mentions and notifications." ],
    "f10" => [ "Guided year-end closing", "Turns on the closing assistant: 18 checked steps from the open fiscal year to the closed one, closing entries in draft, detailed carry-forward, lock, snapshot and bundle, approval and reopening. The direct Close button of the fiscal year is replaced by it." ],
    "f11" => [ "Exchange rates import", "Turns on the daily import of the ECB rates and the monthly import of the InforEuro rates (the only thing that goes to the network). Entering rates, the rate rules and the revaluation are always available." ],
    "f12" => [ "Portfolio and consolidation", "Puts this entity in the portfolio dashboard of the people who work in several entities (a nightly health snapshot, read from its own books only) and lets it be a member of a consolidation group. Each member of a group needs it." ],
    "f13" => [ "Imports, exports and API", "Turns on the guided imports of partners, accounts and entries from CSV and XLSX files (drafts only, taken back by batch), the data exports and the public API." ],
    "agent" => [ "AI assistant", "Turns on the assistant panel: questions about this entity's books, answered from the existing reports with cited figures. It only reads and proposes; nothing is validated, sent or posted without a person. Nothing goes to the language model until an owner has accepted the data-processing consent." ],
    "b01a" => [ "Invoice approval", "Turns on the approval circuit of purchase invoices (the \"bon à payer\"): policies by amount, supplier or project, approvers, delegations, escalation. Without a matching policy an invoice needs no approval, and payment stays possible." ],
    "b01b" => [ "Supplier payments", "Turns on the bank details of suppliers (an account is verified by a second person, after an observation period, before it can be paid) and, later in this feature, the payment batches built from approved invoices. No bank login is ever kept: LedgerFlow prepares a file that you load and authorize in your own bank." ],
    "b03a" => [ "Historical view", "Lets the reports be read as the books were known at a past instant (the balance, the ledgers, the statements, the aged balance, the open lines, the VAT grids): the same figures a reader had then, read only, with the instant on every export. It never changes anything." ],
    "b03c" => [ "Integrity certificate", "Anchors the fingerprints of the validated entries every night (a chain of Merkle roots tied to the audit trail), and issues signed certificates that anyone can verify without access to the application. A certificate proves that the books were not altered since they were anchored; it does not prove that they are right." ],
    "b02a" => [ "Client portal", "Opens a portal on a host of its own to people from outside (a manager, a collaborator, a partner of the client): they see only what the firm publishes to them, can answer and send documents, and never reach the books. Needs the portal host to be configured. Every person signs in with a second factor." ],
    "b03b" => [ "What changed", "A report of what changed in the books between two moments: the entries added, the reversals, the letterings, the changes of setup, the locks, the documents, the payments and the IBANs, the impact on the figures, and the alerts a reviewer should look at first. Reads the history of the books (Historical view); it never changes anything." ],
    "f09" => [ "Customer dunning", "Turns on the preparation of reminders from the open customer lines: levels, texts per language, preview, sending after validation, disputes and payment promises." ]
  }.freeze

  validate :features_are_known
  validates :changes_late_days, :changes_reversals_per_author, :changes_mass_import, :changes_unletterings, numericality: { only_integer: true, in: 1..1000 } # B03b: thresholds of the review alerts
  validates :iban_cooling_hours, numericality: { only_integer: true, in: 0..720 } # B01b: how long a new bank account of a supplier is observed

  # A flag is off unless the owner turned it on. Asking about a feature that does not exist is a bug, not a "no".
  def feature?(name)
    raise ArgumentError, "unknown feature #{name.inspect}" unless FEATURES.include?(name.to_s)

    features[name.to_s] == true
  end

  # Form values ("1"/"0") become booleans; flags that are not sent keep their value.
  def features=(value)
    super(features.merge(value.to_h.stringify_keys.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }))
  end

  # Declared by the entity: turns on everything BudgetFlow-related (API clients, invoice queue, payment feed).
  def budgetflow? = budgetflow_enabled?

  private

  def features_are_known
    unknown = features.keys - FEATURES
    errors.add(:features, "unknown: #{unknown.join(', ')}") if unknown.any?
  end

  def peppol_participant_id_format
    errors.add(:peppol_participant_id, :invalid) unless peppol_participant_id.nil? || Peppol::ParticipantId.valid?(peppol_participant_id)
  end

  # The simulator fakes deliveries: never where the configuration does not allow it (production).
  def simulator_allowed
    return unless peppol_ap_simulator? && !Rails.configuration.x.peppol_simulator_allowed

    errors.add(:peppol_access_point, "the simulator is only available in development and test")
  end

  # What an Access Point needs to be called (API key, secret...) is declared by its adapter.
  def peppol_credentials_complete
    return unless peppol_access_point

    missing = Peppol::AccessPoint.credential_fields(peppol_access_point).select { |f| f[:required] && peppol_credentials[f[:key]].blank? }
    errors.add(:peppol_credentials, "are missing: #{missing.map { |f| f[:label] }.to_sentence}") if missing.any?
  end

  def vat_number_format
    errors.add(:vat_number, :invalid) unless vat_number.blank? || Accounting::Partner.valid_vat_number?(vat_number)
  end

  def rate_fallback_currencies_are_currencies
    unknown = rate_fallback_currencies - Accounting::MoneyPresenter::SUPPORTED_CURRENCIES
    errors.add(:rate_fallback_currencies, "contains unknown currencies: #{unknown.join(', ')}") if unknown.any?
  end
end
