# A download is a link signed for five minutes, for one person and one file; the right is read again when it is followed.
module Portal::DownloadLink
  VALIDITY = 5.minutes

  def self.verifier
    ActiveSupport::MessageVerifier.new(Rails.application.key_generator.generate_key("portal download link"), digest: "SHA256", serializer: JSON, url_safe: true)
  end

  def self.for(person, file) = verifier.generate({ "u" => person.id, "f" => file.token }, expires_in: VALIDITY)

  # The token of the file, or nil: a bad signature, an old link and someone else's link look the same.
  def self.resolve(signed, person)
    payload = verifier.verified(signed.to_s)
    payload["f"] if payload && payload["u"] == person.id
  end
end
