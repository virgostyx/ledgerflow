# F12a: the portfolio: one line per dossier the person works in (and that turned the feature on), read from the health snapshots, never from the books of
# several entities. The actions that can be grouped write no accounting entry: run the checks (R19), notify the people in charge, ask for a backup. What a
# person may do in a dossier is decided by their right in that dossier, entity by entity.
class PortfolioController < ApplicationController
  skip_before_action :require_entity!

  SORTS = {
    "name" => ->(r) { r.entity.name.downcase }, "closing" => ->(r) { [ r.snapshot&.closing_status.to_s, r.entity.name ] },
    "vat" => ->(r) { r.snapshot&.next_vat_due_on || Date.new(9999) }, "blocking" => ->(r) { -(r.snapshot&.blocking_count || -1) },
    "bank" => ->(r) { -(r.snapshot&.unreconciled_bank_lines || 0) }, "receivables" => ->(r) { -(r.snapshot&.overdue_receivables || 0) },
    "last_entry" => ->(r) { r.snapshot&.last_posted_on || Date.new(1) }
  }.freeze
  Row = Struct.new(:entity, :snapshot, :membership, keyword_init: true)

  ACTIONS = {
    "run_checks" => { permission: "closing.adjust", label: "Run the consistency checks" },
    "notify"     => { permission: "tasks.manage",   label: "Notify the people in charge" },
    "export"     => { permission: "exports.backup", label: "Ask for a full backup" }
  }.freeze

  def index
    @organizations = Organization.joins(:organization_memberships).where(organization_memberships: { user_id: current_user.id }).order(:name)
    @members_of = {}
    entities = Portfolio::Access.entities(current_user).includes(:responsible, :organization).to_a
    snapshots = DossierHealthSnapshot.latest_of(entities.map(&:id)).index_by(&:entity_id)
    memberships = UserEntity.current.where(user_id: current_user.id, entity_id: entities.map(&:id)).index_by(&:entity_id)
    rows = entities.map { |entity| Row.new(entity: entity, snapshot: snapshots[entity.id], membership: memberships[entity.id]) }
    @all_count = rows.size
    @rows = filtered(rows).sort_by(&SORTS.fetch(params[:sort].to_s, SORTS["name"]))
    @actions = ACTIONS
    @responsible_choices = responsible_choices(@rows)
  end

  def refresh
    Portfolio::Access.entities(current_user).pluck(:id).each { |id| Portfolio::SnapshotJob.perform_later(id) }
    redirect_to portfolio_path, notice: "The snapshots are being recalculated. Reload in a moment."
  end

  def bulk
    action = ACTIONS[params[:bulk_action].to_s] or return redirect_to(portfolio_path, alert: "Choose an action.")
    return redirect_to(portfolio_path, alert: "Choose at least one dossier.") if Array(params[:entity_ids]).empty?
    return redirect_to(portfolio_path, alert: "Write the message to send.") if params[:bulk_action] == "notify" && params[:message].blank?

    asked = Array(params[:entity_ids]).map(&:to_i).uniq
    entities = Portfolio::Access.entities(current_user).includes(:responsible).where(id: asked).to_a
    allowed = entities.select { |entity| Portfolio::Access.allowed?(current_user, entity, action[:permission]) }
    done = allowed.select { |entity| perform(params[:bulk_action], entity) }
    left_out = asked.size - done.size
    redirect_to portfolio_path, notice: "#{action[:label]}: #{done.size} dossier#{'s' if done.size != 1} done#{", #{left_out} left out (no right there, or already under way)" if left_out.positive?}."
  end

  def responsible
    entity = Portfolio::Access.entities(current_user).find(params[:entity_id])
    return redirect_to(portfolio_path, alert: "Only the owner of a dossier names the person in charge.") unless Portfolio::Access.owner?(current_user, entity)

    person = params[:responsible_id].presence && entity.users.merge(UserEntity.current).find(params[:responsible_id])
    entity.update!(responsible: person)
    ActsAsTenant.with_tenant(entity) { Accounting::AuditLog.record!(auditable: entity, action: "responsible_changed", user: current_user, payload: { responsible: person&.email }) }
    redirect_to portfolio_path, notice: "Saved."
  end

  private

  def filtered(rows)
    rows = rows.select { |r| r.entity.organization_id == params[:organization_id].to_i } if params[:organization_id].present?
    rows = rows.select { |r| params[:responsible] == "me" ? r.entity.responsible_id == current_user.id : r.entity.responsible_id == params[:responsible].to_i } if params[:responsible].present?
    rows = rows.select { |r| r.snapshot&.closing_status == params[:closing] } if params[:closing].present?
    rows = rows.select { |r| vat_matches?(r.snapshot, params[:vat]) } if params[:vat].present?
    rows = rows.select { |r| severity_matches?(r.snapshot, params[:severity]) } if params[:severity].present?
    rows
  end

  def vat_matches?(snapshot, filter)
    return false unless snapshot&.next_vat_due_on

    filter == "overdue" ? snapshot.vat_overdue : snapshot.next_vat_due_on <= Date.current + 30
  end

  def severity_matches?(snapshot, filter)
    case filter
    when "blocking" then snapshot&.blocking_count.to_i.positive?
    when "warnings" then snapshot&.warning_count.to_i.positive?
    when "unchecked" then snapshot.nil? || snapshot.never_checked?
    end
  end

  # The people an owner may name for each of their dossiers: those who work in it today.
  def responsible_choices(rows)
    owned = rows.select { |r| r.membership&.owner? }.map { |r| r.entity.id }
    UserEntity.current.where(entity_id: owned).includes(:user).group_by(&:entity_id).transform_values { |list| list.map(&:user).sort_by(&:full_name) }
  end

  def perform(action, entity)
    ActsAsTenant.with_tenant(entity) do
      case action
      when "run_checks"
        Portfolio::RunChecksJob.perform_later(entity.id)
      when "notify"
        recipients = [ entity.responsible, *(entity.responsible ? [] : UserEntity.current.owners.where(entity_id: entity.id).includes(:user).map(&:user)) ].compact
        recipients.each { |user| Accounting::Notify.call(user: user, event: "portfolio_message:#{entity.id}:#{SecureRandom.hex(4)}", subject: entity, data: { message: params[:message].to_s.first(500), by: current_user.full_name }) }
      when "export"
        next false if DataExport.where(kind: "backup", status: "processing").exists?

        export = DataExport.create!(user: current_user, kind: "backup")
        Exports::BackupJob.perform_later(export.id)
      end
      Accounting::AuditLog.record!(auditable: entity, action: "portfolio_#{action}", user: current_user, payload: { from: "portfolio" })
      true
    end
  end
end
