# What the user changes on an item before validating the run (F09): the recipient, the text, the level, leaving it out. A new level brings the text
# and the charges of that level and drops the confirmation of a skip; a level above the proposed one is a skip, to be confirmed apart.
class Accounting::UpdateDunningItem
  EDITABLE = %i[recipient subject body excluded skip_confirmed].freeze

  def self.call(item:, level: nil, **attrs)
    ctx = LightService::Context.make(item: item)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.already_sent")) } unless item.pending?

    item.assign_attributes(attrs.slice(*EDITABLE))
    change_level(item, level.to_i, attrs) if level && level.to_i != item.level
    item.save!
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.tap { |c| c.fail!(e.message.delete_prefix("Validation failed: ")) }
  end

  def self.change_level(item, level, attrs)
    entity = ActsAsTenant.current_tenant
    policy = Accounting::DunningPolicy.for(entity)
    item.level = level
    item.skip_confirmed = attrs.fetch(:skip_confirmed, false)
    item.fees = policy.fee_for(level) if Accounting::DunningPolicy::LEVELS.include?(level)
    return unless item.valid?

    item.assign_attributes(Accounting::DunningMessage.new(item: item, rows: item.item_lines.includes(line: :journal_entry), policy: policy, entity: entity, on: item.run_on).render)
  end
  private_class_method :change_level
end
