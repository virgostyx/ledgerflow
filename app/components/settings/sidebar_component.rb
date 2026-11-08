class Settings::SidebarComponent < ViewComponent::Base
  def initialize(current_path:)
    @current_path = current_path
  end

  private

  attr_reader :current_path

  # Same right as the API clients and webhooks screens (the member's role in the entity, not the account's global role).
  def manage_integrations?
    Accounting::Settings::BasePolicy.new(helpers.current_user, :settings).destroy?
  end

  def nav_class(match)
    base = "flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium transition-colors"
    if current_path.start_with?(match)
      "#{base} bg-primary-50 text-primary-700"
    else
      "#{base} text-gray-600 hover:bg-gray-50 hover:text-gray-900"
    end
  end
end
