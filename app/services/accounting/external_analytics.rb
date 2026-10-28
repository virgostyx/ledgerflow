# The analytical accounts a third-party application (BudgetFlow) keeps for one of its projects (docs/dev/api/inbound-api.md): one on the
# axis PROJ for the project, one on the axis BUDG for each budget line (sub line), all addressed by the caller's references.
# - upsert: unknown reference -> created; known -> updated in place (code, label); the same payload again changes nothing.
# - a budget line the payload no longer lists is deactivated, never deleted (it may carry annotations); a project that is not active
#   (closed) deactivates all of them.
# - all or nothing. A code already used by an account the caller does not manage is a conflict, not a duplicate.
# Returns a Result whose status is :created, :ok, :unprocessable or :conflict.
class Accounting::ExternalAnalytics
  Result = Struct.new(:status, :project, :budget_lines, :errors, keyword_init: true)
  PROJECT_AXIS = "PROJ".freeze
  BUDGET_AXIS  = "BUDG".freeze

  def self.upsert(ref, payload) = new(ref).upsert(payload.to_h.with_indifferent_access)

  def initialize(ref)
    @ref = ref
  end

  def upsert(payload)
    code   = payload[:code].to_s.strip
    name   = payload[:name].to_s.strip
    active = payload.key?(:active) ? ActiveModel::Type::Boolean.new.cast(payload[:active]) : true
    lines  = Array(payload[:budget_lines]).map { |l| l.to_h.with_indifferent_access }
    errors = input_errors(code, name, lines)
    return failure(:unprocessable, errors) if errors.any?

    proj_axis = Accounting::AnalyticalAxis.find_by(code: PROJECT_AXIS)
    budg_axis = Accounting::AnalyticalAxis.find_by(code: BUDGET_AXIS)
    missing   = { PROJECT_AXIS => proj_axis, BUDGET_AXIS => budg_axis }.select { |_, axis| axis.nil? }.keys
    return failure(:unprocessable, axes: [ "the entity has no analytical axis #{missing.join(' and ')}" ]) if missing.any?

    result = nil
    ApplicationRecord.transaction(requires_new: true) do
      result = write(code, name, active, lines, proj_axis, budg_axis)
      raise ActiveRecord::Rollback unless %i[created ok].include?(result.status)
    end
    result
  rescue ActiveRecord::RecordNotUnique
    failure(:conflict, base: [ "Concurrent update, retry" ])
  end

  private

  def write(code, name, active, lines, proj_axis, budg_axis)
    free_codes_of_removed(code, lines)
    project, created = keep(@ref, proj_axis, code: code, label: name, active: active, key: "code")
    kept = lines.each_with_index.map do |line, i|
      keep(line[:ref], budg_axis, code: "#{code}-#{line[:code].to_s.strip}", label: line[:label].to_s.strip, active: active, key: "budget_lines[#{i}].code").first
    end
    stale = Accounting::AnalyticalAccount.where(external_group: @ref).where.not(external_ref: [ @ref ] + lines.map { |l| l[:ref] })
    stale.update_all(active: false)
    Result.new(status: created ? :created : :ok, project: project, budget_lines: kept)
  rescue ActiveRecord::RecordInvalid => e
    taken = e.record.errors.of_kind?(:code, :taken)
    message = taken ? "The code #{e.record.code.inspect} is already used by another analytical account (one this project does not keep)" : nil
    @failure = failure(taken ? :conflict : :unprocessable, taken ? { base: [ message ] } : { @error_key => e.record.errors.full_messages })
  end

  # A sub line that was removed and a new one that takes its code (a code is reused as soon as a post is deleted and made again): the old account is not the
  # new one, but it keeps its annotations. It gives its code up (code~id), stays inactive, and keeps its reference.
  def free_codes_of_removed(code, lines)
    wanted = lines.to_h { |l| [ "#{code}-#{l[:code].to_s.strip}".downcase, l[:ref] ] }
    removed = Accounting::AnalyticalAccount.where(external_group: @ref).where.not(external_ref: [ @ref ] + lines.map { |l| l[:ref] })
    removed.each do |old|
      next unless wanted.key?(old.code.downcase)

      old.update!(code: "#{old.code[0, 40 - old.id.to_s.size - 1]}~#{old.id}", active: false)
    end
  end

  def keep(ref, axis, code:, label:, active:, key:)
    @error_key = key
    account = Accounting::AnalyticalAccount.find_or_initialize_by(external_ref: ref)
    created = account.new_record?
    account.assign_attributes(analytical_axis: axis, code: code, label_fr: label, active: active, external_group: @ref)
    account.save!
    [ account, created ]
  end

  def input_errors(code, name, lines)
    errors = {}
    errors[:code] = [ "can't be blank" ] if code.blank?
    errors[:name] = [ "can't be blank" ] if name.blank?
    lines.each_with_index do |line, i|
      %i[ref code label].each { |field| (errors["budget_lines[#{i}].#{field}"] ||= []) << "can't be blank" if line[field].to_s.strip.blank? }
    end
    errors
  end

  def failure(status, errors) = Result.new(status: status, errors: errors)
end
