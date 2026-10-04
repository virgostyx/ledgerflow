# The text of a reminder (F09): the entity's own text for a level and a language when it wrote one, else the built-in one. `{{variable}}` are filled
# from `variables`; the variables a text may use are VARIABLES (checked when the policy is saved).
module Accounting::DunningTexts
  LANGUAGES = %w[fr nl en].freeze
  VARIABLES = %w[partner_name entity_name total oldest_days date invoice_list charges grand_total signature].freeze

  DEFAULTS = {
    "en" => {
      1 => [ "Payment reminder", "Dear {{partner_name}},\n\nOur records show that the invoices below are overdue (the oldest by {{oldest_days}} days). This may be an oversight: if you have already paid them, please disregard this message.\n\n{{invoice_list}}\n\nTotal overdue: {{total}}\n{{charges}}\n\nKind regards,\n{{signature}}" ],
      2 => [ "Second reminder", "Dear {{partner_name}},\n\nWe have not received payment of the invoices below, despite our earlier reminder. Please settle them as soon as possible.\n\n{{invoice_list}}\n\nTotal overdue: {{total}}\n{{charges}}\n\nKind regards,\n{{signature}}" ],
      3 => [ "Formal notice", "Dear {{partner_name}},\n\nThe invoices below remain unpaid despite our previous reminders. We formally ask you to pay them without delay. Failing that, we will take further steps to recover the amounts due.\n\n{{invoice_list}}\n\nTotal overdue: {{total}}\n{{charges}}\n\nKind regards,\n{{signature}}" ]
    },
    "fr" => {
      1 => [ "Rappel de paiement", "Madame, Monsieur {{partner_name}},\n\nSauf erreur de notre part, les factures ci-dessous sont échues (la plus ancienne depuis {{oldest_days}} jours). Il s'agit peut-être d'un oubli : si vous les avez déjà payées, veuillez ignorer ce message.\n\n{{invoice_list}}\n\nTotal échu : {{total}}\n{{charges}}\n\nCordialement,\n{{signature}}" ],
      2 => [ "Second rappel", "Madame, Monsieur {{partner_name}},\n\nNous n'avons pas reçu le paiement des factures ci-dessous, malgré notre précédent rappel. Nous vous prions de les régler dans les meilleurs délais.\n\n{{invoice_list}}\n\nTotal échu : {{total}}\n{{charges}}\n\nCordialement,\n{{signature}}" ],
      3 => [ "Mise en demeure", "Madame, Monsieur {{partner_name}},\n\nLes factures ci-dessous restent impayées malgré nos rappels. Nous vous mettons en demeure de les payer sans délai. À défaut, nous engagerons les démarches nécessaires au recouvrement des sommes dues.\n\n{{invoice_list}}\n\nTotal échu : {{total}}\n{{charges}}\n\nCordialement,\n{{signature}}" ]
    },
    "nl" => {
      1 => [ "Betalingsherinnering", "Geachte {{partner_name}},\n\nVolgens onze gegevens zijn onderstaande facturen vervallen (de oudste sinds {{oldest_days}} dagen). Het kan een vergetelheid zijn: indien u ze al betaald hebt, mag u dit bericht negeren.\n\n{{invoice_list}}\n\nTotaal vervallen: {{total}}\n{{charges}}\n\nMet vriendelijke groeten,\n{{signature}}" ],
      2 => [ "Tweede herinnering", "Geachte {{partner_name}},\n\nWij hebben de betaling van onderstaande facturen niet ontvangen, ondanks onze vorige herinnering. Wij verzoeken u deze zo spoedig mogelijk te betalen.\n\n{{invoice_list}}\n\nTotaal vervallen: {{total}}\n{{charges}}\n\nMet vriendelijke groeten,\n{{signature}}" ],
      3 => [ "Ingebrekestelling", "Geachte {{partner_name}},\n\nOnderstaande facturen blijven onbetaald ondanks onze herinneringen. Wij stellen u hierbij in gebreke en verzoeken u onverwijld te betalen. Zo niet, dan zullen wij de nodige stappen ondernemen om de verschuldigde bedragen te innen.\n\n{{invoice_list}}\n\nTotaal vervallen: {{total}}\n{{charges}}\n\nMet vriendelijke groeten,\n{{signature}}" ]
    }
  }.freeze

  CHARGE_LABELS = {
    "en" => { fees: "Reminder fee", interest: "Late interest", indemnity: "Fixed indemnity", grand_total: "Total to pay" },
    "fr" => { fees: "Frais de rappel", interest: "Intérêts de retard", indemnity: "Indemnité forfaitaire", grand_total: "Total à payer" },
    "nl" => { fees: "Herinneringskosten", interest: "Verwijlinteresten", indemnity: "Forfaitaire schadevergoeding", grand_total: "Totaal te betalen" }
  }.freeze

  # The lines under the total when the reminder adds something to it ("" when it does not), from the amounts already formatted.
  def self.charges_text(language:, amounts:, grand_total:)
    labels = CHARGE_LABELS.fetch(language.to_s) { CHARGE_LABELS.fetch("en") }
    lines  = amounts.filter_map { |key, text| "#{labels.fetch(key)}: #{text}" if text }
    lines.empty? ? "" : (lines + [ "#{labels.fetch(:grand_total)}: #{grand_total}" ]).join("\n")
  end

  def self.render(policy:, level:, language:, variables:)
    subject, body = template(policy, level, language)
    { subject: fill(subject, variables), body: fill(body, variables).gsub(/\n{3,}/, "\n\n").strip }
  end

  # An error message per fault in the texts the entity wrote, [] when they are fine.
  def self.errors_in(templates)
    templates.flat_map do |level, languages|
      next [ "Unknown level #{level}" ] unless Accounting::DunningPolicy::LEVELS.map(&:to_s).include?(level.to_s)

      languages.flat_map do |language, text|
        next [ "Unknown language #{language}" ] unless LANGUAGES.include?(language.to_s)

        unknown = text.values_at("subject", "body").flat_map { |t| t.to_s.scan(/\{\{(\w+)\}\}/).flatten } - VARIABLES
        unknown.uniq.map { |name| "Unknown variable {{#{name}}} in level #{level} (#{language})" }
      end
    end
  end

  # [subject, body] the entity wrote for this level and language, else the built-in text.
  def self.template(policy, level, language)
    own = policy.templates.dig(level.to_s, language.to_s)
    return own.values_at("subject", "body") if own&.values_at("subject", "body")&.all?(&:present?)

    built_in(level, language)
  end

  def self.built_in(level, language) = DEFAULTS.fetch(language.to_s) { DEFAULTS.fetch("en") }.fetch(level.to_i)

  def self.fill(text, variables) = text.gsub(/\{\{(\w+)\}\}/) { variables.fetch(Regexp.last_match(1).to_sym, "") }
  private_class_method :fill
end
