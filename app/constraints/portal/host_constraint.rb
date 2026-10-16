# B02a: tells the host of the client portal from the others (the application, the proxy's health checks come first in the routes).
class Portal::HostConstraint
  def self.host = Rails.configuration.x.portal_host

  def initialize(portal:)
    @portal = portal
  end

  def matches?(request) = (request.host == self.class.host) == @portal
end
