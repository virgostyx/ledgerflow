# Access Points (APs) are the providers that carry documents over the Peppol network. Each entity chooses its own
# (Entity#peppol_access_point) and there is ONE adapter per provider, not per entity: two entities with the same
# provider share the adapter and differ by their credentials. An adapter implements Peppol::AccessPoint::Base.
module Peppol::AccessPoint
  class Error < StandardError; end
  class NotConfigured < Error; end
  class InvalidSignature < Error; end

  PROVIDERS = {
    "simulator" => "Peppol::AccessPoint::Simulator",
    "digiteal"  => "Peppol::AccessPoint::Digiteal"
  }.freeze

  def self.for(entity)
    provider = entity.peppol_access_point or raise NotConfigured, "No Peppol Access Point is set up for this entity"

    provider_class(provider).new(entity)
  end

  def self.provider_class(provider) = PROVIDERS.fetch(provider.to_s).constantize

  # What the settings screen must ask for a provider, without building an adapter.
  def self.credential_fields(provider) = provider_class(provider).credential_fields
end
