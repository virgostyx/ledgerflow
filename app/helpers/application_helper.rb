module ApplicationHelper
  # Returns Tailwind classes for a sidebar nav link.
  # Marks the link active when the current request path matches any of the given paths
  # (exact match OR prefix match with a trailing slash).
  #
  # Usage:
  #   link_to path, class: nav_class(path)
  #   link_to path, class: nav_class([path1, path2])
  def nav_class(*paths)
    paths = paths.flatten
    active = paths.any? do |path|
      request.path == path || request.path.start_with?("#{path}/")
    end
    base = "flex items-center gap-3 px-3 py-2 rounded-md text-sm font-medium transition-colors"
    if active
      "#{base} bg-primary-100 text-primary-700"
    else
      "#{base} text-gray-600 hover:bg-primary-50 hover:text-primary-700"
    end
  end

  # Returns up to two uppercase initials from a full name.
  # Falls back to "?" when name is blank.
  def user_initials(name)
    return "?" if name.blank?
    name.split.first(2).map { |w| w[0].upcase }.join
  end
end
