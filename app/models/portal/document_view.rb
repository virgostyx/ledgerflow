# B02c: that a person opened a file of a publication (through a download link), once. The decision of approval is open only to someone who opened every file.
class Portal::DocumentView < ApplicationRecord
  belongs_to :publication_file, class_name: "Portal::PublicationFile"
  belongs_to :portal_user

  def self.record!(file, person)
    create_with(viewed_at: Time.current).find_or_create_by!(publication_file_id: file.id, portal_user_id: person.id)
  rescue ActiveRecord::RecordNotUnique
    find_by!(publication_file_id: file.id, portal_user_id: person.id)
  end
end
