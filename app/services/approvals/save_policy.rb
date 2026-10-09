# Writes an approval policy and its levels (B01a), all or nothing. A policy that requests were made under is not edited under
# their feet: when its levels change it is retired and a new version takes its place (the requests keep the old levels, the next
# invoices meet the new ones). Its name, priority, conditions and timing may change in place: requests do not depend on them.
# attributes: name, priority, active, conditions, reminder_hours. steps: [{ mode:, approver_user_ids:, approver_roles:, service_hours:, escalate_to_id: }], in order.
# => ctx[:policy]
class Approvals::SavePolicy
  OWN_FIELDS = %i[mode approver_user_ids approver_roles service_hours escalate_to_id].freeze
  DOCUMENT_TYPES = %w[invoice credit_note].freeze

  def self.call(policy:, attributes:, steps:)
    ctx = LightService::Context.make(policy: policy)
    steps = Array(steps).map { |step| clean_step(step) }.reject { |step| blank_step?(step) }
    return ctx.tap { |c| c.fail!(I18n.t("approvals.policy.errors.no_level")) } if steps.empty?

    ApplicationRecord.transaction do
      ctx[:policy] = write(policy, clean_attributes(attributes), steps)
    end
    ctx
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail!(e.record.is_a?(Approvals::Step) ? I18n.t("approvals.policy.errors.level", position: e.record.position, message: e.record.errors.full_messages.to_sentence) : e.record.errors.full_messages.to_sentence)
    ctx
  rescue ArgumentError => e
    ctx.fail!(e.message)
    ctx
  end

  def self.write(policy, attributes, steps)
    return create(Approvals::Policy.new(attributes), steps) unless policy&.persisted?
    return update_in_place(policy, attributes, steps) unless policy.requests.exists? && levels_differ?(policy, steps)

    successor = create(Approvals::Policy.new(attributes.merge(version: policy.version + 1)), steps)
    policy.update!(active: false)
    Accounting::AuditLog.record!(auditable: successor, action: "approval_policy_revised", payload: { replaces: policy.id, version: successor.version })
    successor
  end
  private_class_method :write

  def self.create(policy, steps)
    policy.save!
    build_steps(policy, steps)
    policy
  end
  private_class_method :create

  def self.update_in_place(policy, attributes, steps)
    policy.update!(attributes)
    unless policy.requests.exists?
      policy.steps.destroy_all
      build_steps(policy, steps)
    end
    policy
  end
  private_class_method :update_in_place

  def self.build_steps(policy, steps)
    steps.each_with_index { |step, index| policy.steps.create!(step.merge(position: index + 1)) }
  end
  private_class_method :build_steps

  def self.levels_differ?(policy, steps)
    policy.steps.map { |s| OWN_FIELDS.index_with { |f| s.public_send(f) } } != steps.map { |s| OWN_FIELDS.index_with { |f| normalize(s[f], f) } }
  end
  private_class_method :levels_differ?

  def self.normalize(value, field)
    value = (value.presence || nil) if field == :escalate_to_id || field == :service_hours
    value
  end
  private_class_method :normalize

  def self.clean_step(step)
    step = step.to_h.symbolize_keys
    { mode: step[:mode].presence || "any_of",
      approver_user_ids: Array(step[:approver_user_ids]).compact_blank.map(&:to_i).uniq,
      approver_roles: Array(step[:approver_roles]).compact_blank.uniq,
      service_hours: step[:service_hours].presence&.to_i,
      escalate_to_id: step[:escalate_to_id].presence&.to_i }
  end
  private_class_method :clean_step

  def self.blank_step?(step) = step[:approver_user_ids].empty? && step[:approver_roles].empty? && step[:service_hours].nil? && step[:escalate_to_id].nil?
  private_class_method :blank_step?

  def self.clean_attributes(attributes)
    attributes = attributes.to_h.symbolize_keys
    cleaned = attributes.slice(:name, :priority, :active, :reminder_hours).merge(subject: :purchase_invoice)
    cleaned[:conditions] = clean_conditions(attributes[:conditions] || {})
    cleaned[:reminder_hours] = Array(cleaned[:reminder_hours]).compact_blank.map(&:to_i).sort if cleaned.key?(:reminder_hours)
    cleaned.compact
  end
  private_class_method :clean_attributes

  # Only what is filled in, typed: amounts as given (digits), ids as integers, currencies upper case, a closed list of document types.
  def self.clean_conditions(raw)
    raw = raw.to_h.symbolize_keys
    conditions = {}
    %i[min_amount max_amount].each do |key|
      next if raw[key].blank?

      Float(raw[key].to_s.tr(",", ".")) rescue raise(ArgumentError, I18n.t("approvals.policy.errors.amount", amount: raw[key]))
      conditions[key.to_s] = raw[key].to_s
    end
    %i[partner_ids account_ids project_ids].each do |key|
      ids = list(raw[key]).map(&:to_i)
      conditions[key.to_s] = ids if ids.any?
    end
    currencies = list(raw[:currencies]).map(&:upcase)
    conditions["currencies"] = currencies if currencies.any?
    types = list(raw[:document_types]) & DOCUMENT_TYPES
    conditions["document_types"] = types if types.any?
    conditions["first_payment"] = true if ActiveModel::Type::Boolean.new.cast(raw[:first_payment])
    conditions
  end
  private_class_method :clean_conditions

  # A list typed as "3, 9" or sent as an array with an empty value for the form's sake.
  def self.list(value) = (value.is_a?(String) ? value.split(",") : Array(value)).map { |v| v.to_s.strip }.compact_blank
  private_class_method :list
end
