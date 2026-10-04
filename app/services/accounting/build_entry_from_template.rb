# F07: a draft entry from an entry template, at a date. `base_amount` is the amount the percentage lines are taken of; `inputs` maps the id of
# a typed line to its amount. The entry is created only when it balances and its accounts are usable (an archived one is named); it is
# never posted here. => ctx[:entry]
class Accounting::BuildEntryFromTemplate
  def self.call(template:, date:, base_amount: nil, inputs: {}, user: nil)
    ctx = LightService::Context.make(template: template)
    inputs = (inputs || {}).transform_keys(&:to_s)
    amounts = amounts_for(template, base_amount, inputs)
    return ctx.tap { |c| c.fail!(amounts) } if amounts.is_a?(String)

    problem = problem_with(template, amounts, date)
    return ctx.tap { |c| c.fail!(problem) } if problem

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      entry = Accounting::JournalEntry.create!(journal: template.journal, fiscal_year: fiscal_year_at(date), entry_date: date, status: :draft, created_by: user,
                                               description: Accounting::EntryTemplate.interpolate(template.description, date))
      template.lines.each_with_index do |line, i|
        amount = amounts.fetch(line.id)
        entry.lines.create!(account: line.account, partner: line.partner, vat_code: line.vat_code, sort_order: i,
                            label: Accounting::EntryTemplate.interpolate(line.label, date),
                            debit: (line.debit? ? amount : 0), credit: (line.credit? ? amount : 0))
      end
      ctx[:entry] = entry
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.message)
  end

  # What the entry would weigh (its total debit) for a base amount, or nil when the template cannot be worked out from it alone (forecasts).
  def self.total_for(template, base_amount)
    amounts = amounts_for(template, base_amount, {})
    amounts.is_a?(String) ? nil : template.lines.select(&:debit?).sum { |l| amounts.fetch(l.id) }
  end

  # => { line id => BigDecimal }, or a String (what is missing)
  def self.amounts_for(template, base_amount, inputs)
    return I18n.t("accounting.entry_templates.errors.base_required") if template.needs_base? && base_amount.blank?

    template.lines.to_h do |line|
      amount = case line.amount_kind
      when "fixed"   then line.amount
      when "percent" then (BigDecimal(base_amount.to_s) * line.percentage / 100).round(2, half: :up)
      else
        return I18n.t("accounting.entry_templates.errors.input_required", label: line.label.presence || line.account.code) if inputs[line.id.to_s].blank?

        BigDecimal(inputs[line.id.to_s].to_s).round(2, half: :up)
      end
      [ line.id, amount ]
    end
  rescue ArgumentError, TypeError
    I18n.t("accounting.entry_templates.errors.invalid_amount")
  end

  def self.problem_with(template, amounts, date)
    archived = template.lines.map(&:account).reject(&:active?).map(&:code).uniq
    return I18n.t("accounting.entry_templates.errors.archived_account", codes: archived.join(", ")) if archived.any?
    return I18n.t("accounting.entry_templates.errors.no_fiscal_year", date: I18n.l(date)) unless fiscal_year_at(date)

    debit  = template.lines.select(&:debit?).sum { |l| amounts.fetch(l.id) }
    credit = template.lines.select(&:credit?).sum { |l| amounts.fetch(l.id) }
    I18n.t("accounting.entry_templates.errors.unbalanced", debit: debit, credit: credit) unless debit == credit
  end

  def self.fiscal_year_at(date) = Accounting::FiscalYear.open.find_by("start_date <= :d AND end_date >= :d", d: date)
  private_class_method :amounts_for, :problem_with, :fiscal_year_at
end
