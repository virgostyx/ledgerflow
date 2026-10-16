class Portal::PublicationFile < ApplicationRecord
  belongs_to :publication, class_name: "Portal::Publication", inverse_of: :files

  def to_param = token

  # The bytes are only read when a file is served, and checked against the SHA-256 written at publication.
  def intact? = Digest::SHA256.hexdigest(content) == sha256
end
