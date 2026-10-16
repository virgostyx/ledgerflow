# B02c: a person who may approve a publication (named by the firm when it publishes). Frozen with the publication.
class Portal::PublicationApprover < ApplicationRecord
  belongs_to :publication, class_name: "Portal::Publication", inverse_of: :approver_rows
  belongs_to :portal_user
end
