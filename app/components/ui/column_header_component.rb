# Column header with a sort/filter dropdown, in the spirit of a spreadsheet AutoFilter.
# The column must be declared on the model with `autofilter_column`.
class Ui::ColumnHeaderComponent < ViewComponent::Base
  def initialize(model:, key:, label:, resource:, query:, path:, align: :left, extra: {})
    @model    = model
    @key      = key.to_s
    @label    = label
    @resource = resource
    @query    = query.to_h.deep_stringify_keys
    @path     = path
    @align    = align
    @extra    = extra
    @column   = model.autofilter_columns.fetch(@key)
  end

  attr_reader :key, :label, :path, :column

  def type      = column[:type]
  def filter?   = column[:filter]
  def selected  = @query.dig("f", key)
  def active?   = selected.present?
  def sorted    = (@query["sort"] == key ? @query["dir"] : nil)
  def menu_side = @align == :right ? "right-0" : "left-0"

  def sort_url(dir)
    "#{path}?#{@query.except('page').merge('sort' => key, 'dir' => dir).to_query}"
  end

  def clear_url
    "#{path}?#{without_own_filter.except('page').to_query}"
  end

  def values_url
    helpers.accounting_column_values_path(@resource, key, @extra.merge(@query.slice("q", "f")))
  end

  def enum_options
    return [ %w[Active true], %w[Inactive false] ] if type == :boolean

    @model.defined_enums.fetch(column[:sql].split(".").last).keys.map { |k| [ k.humanize, k ] }
  end

  def range_value(bound) = selected.is_a?(Hash) ? selected[bound] : nil

  # [name, value] pairs for every current param except this column's own filter and the page.
  def hidden_fields
    flatten(without_own_filter.except("page"))
  end

  private

  def without_own_filter
    f = (@query["f"] || {}).except(key)
    @query.merge("f" => f).reject { |_, v| v.blank? }
  end

  def flatten(value, prefix = nil)
    case value
    when Hash  then value.flat_map { |k, v| flatten(v, prefix ? "#{prefix}[#{k}]" : k.to_s) }
    when Array then value.flat_map { |v| flatten(v, "#{prefix}[]") }
    else [ [ prefix, value ] ]
    end
  end
end
