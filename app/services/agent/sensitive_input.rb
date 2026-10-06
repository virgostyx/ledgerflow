# Looks, in what a person is about to send to the agent, for what must not leave as it is (A04): an IBAN, a national number, a bank card number, a password. It says what each one
# would become, from the entity's settings, so that the person is told before anything is sent. A card number and a password never go, whatever the settings.
module Agent::SensitiveInput
  PASSWORD = /\b(mot de passe|password|wachtwoord|pwd|passcode)\s*[:=]\s*\S+/i

  Finding = Data.define(:kind, :effect, :count)
  Review = Data.define(:findings) do
    def clear? = findings.empty?
    def blocked? = findings.any? { |finding| finding.effect == :block }
  end

  def self.review(text, setting)
    text = text.to_s
    found = []
    ibans = Agent::Identifiers.ibans(text).size
    numbers = text.scan(Agent::Identifiers::NATIONAL_NUMBER).count { |raw| Agent::Identifiers.national_number?(raw) }
    cards = text.scan(Agent::Identifiers::CARD).count { |raw| Agent::Identifiers.card?(raw) }
    found << Finding.new(:iban, effect_of(setting.mode_for(:bank_identifier)), ibans) if ibans.positive?
    found << Finding.new(:national_number, effect_of(setting.mode_for(:personal)), numbers) if numbers.positive?
    found << Finding.new(:card, :block, cards) if cards.positive?
    found << Finding.new(:password, :block, text.scan(PASSWORD).size) if text.match?(PASSWORD)
    Review.new(found)
  end

  def self.effect_of(mode) = { "send" => :send, "mask" => :mask, "block" => :block }.fetch(mode)
end
