# Looks, in text that comes from the data (a label, a name, a remark, a document), for what is written to an AI rather than to a person: an order to ignore the rules, a role
# marker, a request to send something out, a link, an encoded block, hidden characters, a request for a secret (A03). It is NOT a defence: whatever it misses is stopped by the
# architecture (no write tool, no way out, rights read at every call). It raises an alert and gives something to measure.
module Agent::InjectionDetector
  PATTERNS = {
    instruction_override: [
      /\b(ignore|disregard|forget|override)\b.{0,30}\b(instructions?|rules|prompts?|guidelines|above|previous|prior)\b/i,
      /\b(you are now|new instructions|system prompt)\b/i,
      /\bignore[zr]?\b.{0,30}\b(instructions|consignes|r[eè]gles)\b/i,
      /\boubli(e|ez)\b.{0,20}\b(tes|vos|les|toutes|tout)\b/i,
      /\b(tu es maintenant|vous [eê]tes maintenant|nouvelles? (consignes|instructions))\b/i,
      /\bnegeer\b.{0,30}\b(instructies|regels|opdrachten)\b/i,
      /\bvergeet\b.{0,20}\b(je|alle|de)\b/i
    ],
    role_marker: [ /^\s*(system|assistant|human|developer)\s*:/i, /\b(system|assistant|developer)\s*:\s*(you|i will|obey|ignore|disregard|grant|disable|the user|new)\b/i, %r{</?\s*(system|instructions?|tool_data|tool_result|im_start|im_end)\b}i, /\[\/?INST\]/ ],
    addressed_to_ai: [ /\b(notes?|messages?|instructions?|attention|note)\s+(to|for|[àa]|pour|voor)\s+(the\s+|l['’]\s*|de\s+)?(ai|assist[ae]nt|llm|model|agent|ia)\b/i ],
    exfiltration: [ /\b(send|email|mail|post|forward|upload|envoie[rz]?|stuur|verstuur)\b.{0,60}\b(to|[àa]|naar)\b.{0,40}(@|https?:)/i ],
    url: [ %r{https?://|\bwww\.}i ],
    encoded_block: [ %r{[A-Za-z0-9+/]{80,}={0,2}} ],
    control_sequence: [ /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁠-⁩﻿]/ ],
    secret_request: [
      /\b(reveal|show|print|display|give|tell|donne|donne-moi|affiche|montre|toon|geef)\b.{0,40}\b(api[ _-]?keys?|passwords?|mot de passe|wachtwoord|tokens?|secrets?|credentials?)\b/i,
      /\b(api[ _-]?keys?|passwords?|mot de passe|wachtwoord|tokens?|secrets?)\b.{0,30}\b(reveal|show|print|display|give|tell|donne|affiche|montre|toon|geef)\b/i
    ]
  }.freeze

  # The names of the patterns found in the text, each once, in the order of PATTERNS.
  def self.scan(text)
    return [] if text.blank?

    PATTERNS.filter_map { |name, regexes| name if regexes.any? { |regex| text.match?(regex) } }
  end
end
