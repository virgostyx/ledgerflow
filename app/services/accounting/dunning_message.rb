# The subject and the body of the reminder of an item, from the text of its level and language filled with the figures of the item (F09).
class Accounting::DunningMessage
  # `rows` are what the item covers: anything with `reference`, `due_date`, `age_days` and `residual`.
  def initialize(item:, rows:, policy:, entity:, on:)
    @item, @rows, @policy, @entity, @on = item, rows, policy, entity, on
  end

  def render
    Accounting::DunningTexts.render(policy: @policy, level: @item.level, language: @item.language, variables: variables)
  end

  private

  def variables
    {
      partner_name: @item.partner.name, entity_name: @entity.legal_name, total: money(@item.total),
      oldest_days: @rows.map(&:age_days).max.to_s, date: Accounting::DatePresenter.new(@on).format, invoice_list: invoice_list,
      charges: charges, grand_total: money(@item.grand_total), signature: @policy.signature.presence || @entity.legal_name
    }
  end

  def invoice_list
    @rows.sort_by(&:due_date).map do |r|
      "- #{r.reference.presence || '—'} (#{Accounting::DatePresenter.new(r.due_date).format}): #{money(r.residual)}"
    end.join("\n")
  end

  def charges
    amounts = { fees: @item.fees, interest: @item.interest, indemnity: @item.indemnity }.transform_values { |v| money(v) if v.positive? }
    Accounting::DunningTexts.charges_text(language: @item.language, amounts: amounts, grand_total: money(@item.grand_total))
  end

  def money(amount) = Accounting::MoneyPresenter.new(amount).format
end
