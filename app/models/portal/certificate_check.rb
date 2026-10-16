# B02c: what the firm's side last found about the certificate of a publication. Read by the portal; written only by PortalAdmin::CheckPublicationCertificates.
class Portal::CertificateCheck < ApplicationRecord
  STATES = %w[valid revoked not_valid unknown].freeze

  belongs_to :publication, class_name: "Portal::Publication"
  validates :state, inclusion: { in: STATES }
end
