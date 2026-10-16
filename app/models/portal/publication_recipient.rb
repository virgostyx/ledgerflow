class Portal::PublicationRecipient < ApplicationRecord
  belongs_to :publication, class_name: "Portal::Publication", inverse_of: :recipient_rows
  belongs_to :portal_user
end
