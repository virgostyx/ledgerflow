# A line was disputed or promised (F09): the prepared reminders that still cover it let it go, so that nothing asks for what is no longer asked for.
# The amounts and the charges follow; the text is written again unless a person wrote it; a reminder left with no line is left out of its run. A
# reminder already sent is history and is not touched.
class Accounting::RefreshDunningItems
  def self.call(line:)
    Accounting::DunningItem.pending.joins(:item_lines).where(dunning_item_lines: { line_id: line.id }).includes(:partner, :run).find_each do |item|
      refresh(item, line)
    end
  end

  def self.refresh(item, line)
    entity = ActsAsTenant.current_tenant
    policy = Accounting::DunningPolicy.for(entity)
    untouched = text(item, policy, entity) == item.slice(:subject, :body).symbolize_keys
    item.item_lines.where(line_id: line.id).destroy_all if line.disputed || (line.payment_promised_on && line.payment_promised_on >= item.run_on)
    rows = item.item_lines.reload.includes(line: :journal_entry).to_a
    return item.update!(excluded: true) if rows.empty?

    item.update!(total: rows.sum(&:amount), **Accounting::DunningCharges.call(policy: policy, level: item.level, rows: rows).slice(:interest))
    item.update!(text(item, policy, entity, rows)) if untouched
  end
  private_class_method :refresh

  def self.text(item, policy, entity, rows = item.item_lines.includes(line: :journal_entry).to_a)
    Accounting::DunningMessage.new(item: item, rows: rows, policy: policy, entity: entity, on: item.run_on).render
  end
  private_class_method :text
end
