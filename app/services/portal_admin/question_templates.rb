# B02c: frequent questions, by language of the client (the firm picks one, reads it, then asks). A template is only text: the firm still chooses the target and may change every word.
class PortalAdmin::QuestionTemplates
  ALL = {
    "professional" => {
      "answer_type" => "single",
      "en" => { title: "Is this expense professional?", choices: [ [ "yes", "Yes" ], [ "no", "No" ], [ "part", "Partly (tell us the percentage)" ] ] },
      "fr" => { title: "Cette dépense est-elle professionnelle ?", choices: [ [ "yes", "Oui" ], [ "no", "Non" ], [ "part", "En partie (indiquez le pourcentage)" ] ] },
      "nl" => { title: "Is deze uitgave zakelijk?", choices: [ [ "yes", "Ja" ], [ "no", "Nee" ], [ "part", "Gedeeltelijk (geef het percentage aan)" ] ] }
    },
    "what_for" => {
      "answer_type" => "text",
      "en" => { title: "What does this payment correspond to?", choices: [] },
      "fr" => { title: "À quoi correspond ce paiement ?", choices: [] },
      "nl" => { title: "Waarvoor dient deze betaling?", choices: [] }
    },
    "invoice" => {
      "answer_type" => "file",
      "en" => { title: "Could you send us the invoice?", choices: [] },
      "fr" => { title: "Pouvez-vous nous fournir la facture ?", choices: [] },
      "nl" => { title: "Kunt u ons de factuur bezorgen?", choices: [] }
    }
  }.freeze

  def self.keys = ALL.keys

  # => { title:, answer_type:, choices: [{ key:, label: }] } in the language, English when it has none
  def self.fetch(key, language)
    template = ALL.fetch(key)
    text = template[language.to_s] || template.fetch("en")
    { title: text[:title], answer_type: template["answer_type"], choices: text[:choices].map { |k, label| { key: k, label: label } } }
  end
end
