# The last check on what the model wrote, before it is stored or shown (A03): an address it could use to carry data out (a link, an image) and anything that looks like a key or a
# token are taken out. Links to the books are never the model's to write: the application builds them from checked references.
module Agent::ResponseGuard
  SECRETS = [
    /sk-ant-[A-Za-z0-9_-]{10,}/, /\bsk-[A-Za-z0-9]{20,}/, /\bAKIA[0-9A-Z]{16}\b/, /\blf_[A-Za-z0-9_-]{20,}/, /\bwhsec_[A-Za-z0-9_-]{20,}/,
    /\bBearer\s+[A-Za-z0-9._~+\/-]{20,}=*/, /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+/,
    /-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|\z)/m
  ].freeze
  ADDRESS = %r{(?:https?://|\bwww\.)[^\s)>\]"']+}i

  # => [clean text, [:secret_removed, :url_removed] as found]
  def self.clean(text)
    kinds = []
    cleaned = text.to_s.dup
    SECRETS.each { |secret| cleaned.gsub!(secret) { kinds << :secret_removed; "[secret removed]" } }
    cleaned.gsub!(ADDRESS) { kinds << :url_removed; "[link removed]" }
    [ cleaned, kinds.uniq ]
  end
end
