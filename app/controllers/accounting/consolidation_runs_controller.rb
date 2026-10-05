# F12b: the consolidation of a group at a date, step by step: scope, collection, translation, eliminations, minority interests, review, freeze. A run is refused whole
# to someone who has no access to every member company. Nothing here writes in the books of any company.
class Accounting::ConsolidationRunsController < ApplicationController
  before_action { require_feature!(:f12) }
  before_action :set_run, except: :create
  before_action :require_every_member, except: :create

  def create
    group = Consolidation::Group.find(params[:group_id])
    authorize :consolidation, :create?, policy_class: Accounting::ConsolidationPolicy
    missing = Consolidation::Access.missing(current_user, group)
    return redirect_to(accounting_consolidation_groups_path, alert: "You do not have access to every company of this group (#{missing} missing): refused whole.") if missing.positive?

    date = Date.iso8601(params[:reporting_date].to_s)
    run = group.runs.create!(reporting_date: date, entity: group.entity, created_by: current_user)
    Consolidation::Compute.call(run)
    redirect_to accounting_consolidation_run_path(run), notice: "Run worked out."
  rescue Date::Error
    redirect_to accounting_consolidation_group_path(group), alert: "Give the reporting date, YYYY-MM-DD."
  end

  def show
    authorize :consolidation, :show?, policy_class: Accounting::ConsolidationPolicy
    @view = Consolidation::RunView.new(@run)
    @diff = Consolidation::Diff.call(@run)
    @group = @run.group
    @documents = Accounting::Document.order(:name).limit(200) if @run.draft?
  end

  def compute
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    return redirect_to(accounting_consolidation_run_path(@run), alert: "A #{@run.status} run is not worked out again.") unless @run.draft?

    Consolidation::Compute.call(@run)
    redirect_to accounting_consolidation_run_path(@run), notice: "Worked out again from the books."
  end

  def validate
    authorize :consolidation, :approve?, policy_class: Accounting::ConsolidationPolicy
    Consolidation::Finalize.validate!(@run, current_user)
    audit("consolidation_run_validated")
    redirect_to accounting_consolidation_run_path(@run), notice: "Validated: nothing blocks. Freeze it when you are ready."
  rescue Consolidation::Finalize::Refused => e
    redirect_to accounting_consolidation_run_path(@run), alert: e.message
  end

  def freeze
    authorize :consolidation, :approve?, policy_class: Accounting::ConsolidationPolicy
    Consolidation::Finalize.freeze!(@run, current_user)
    audit("consolidation_run_frozen", sha256: @run.snapshot_sha256)
    redirect_to accounting_consolidation_run_path(@run), notice: "Frozen. Its fingerprint: #{@run.snapshot_sha256}."
  rescue Consolidation::Finalize::Refused => e
    redirect_to accounting_consolidation_run_path(@run), alert: e.message
  end

  # A manual entry, or the proposal of an adjustment that explains a difference between two companies (pre-filled; nothing is saved before the person confirms).
  def new_entry
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    @entry = @run.entries.build(kind: params[:kind].presence || "adjustment", context: params.permit(context: {})[:context].to_h)
    @entry.comment = params[:comment]
    prefilled(@entry)
    @documents = Accounting::Document.order(:name).limit(200)
  end

  def create_entry
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    entry = @run.entries.build(kind: params[:kind], comment: params[:comment], document_id: params[:document_id].presence, context: params.permit(context: {})[:context].to_h, created_by: current_user)
    lines = params[:lines]
    (lines.respond_to?(:values) ? lines.values : Array(lines)).each { |line| entry.lines.build(line.permit(:statement, :code, :side, :amount)) if line[:code].present? }
    if entry.save
      Consolidation::Compute.call(@run)
      redirect_to accounting_consolidation_run_path(@run), notice: "Entry recorded; the run is worked out again."
    else
      redirect_to new_entry_accounting_consolidation_run_path(@run, kind: entry.kind), alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy_entry
    authorize :consolidation, :update?, policy_class: Accounting::ConsolidationPolicy
    entry = @run.entries.find(params[:entry_id])
    return redirect_to(accounting_consolidation_run_path(@run), alert: "An entry proposed by a validated rule is not deleted: revoke the validation or change the books.") if entry.rule_key

    entry.destroy
    Consolidation::Compute.call(@run)
    redirect_to accounting_consolidation_run_path(@run), notice: "Entry deleted; the run is worked out again."
  end

  def export
    authorize :consolidation, :show?, policy_class: Accounting::ConsolidationPolicy
    view = Consolidation::RunView.new(@run)
    result = Reports::Result.new(rows: export_rows(view), currency: @run.group.currency)
    columns = [ [ "Section", :section ], [ "Code", :code ], [ "Label", :label ], [ "Amount", :amount ] ]
    title = "Consolidation #{@run.group.name} at #{@run.reporting_date}#{' (PROVISIONAL)' if @run.provisional}"
    filename = "consolidation_#{@run.reporting_date}"
    audit("consolidation_export", format: params[:format].to_s)
    case params[:format]
    when "xlsx" then send_data Reports::Exporters::Xlsx.call(result, columns: columns, title: title.first(31)), filename: "#{filename}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    when "pdf" then send_data Reports::Exporters::Pdf.call(result, columns: columns, title: title, watermark: nil), filename: "#{filename}.pdf", type: "application/pdf"
    else head :not_found
    end
  end

  private

  def set_run = @run = Consolidation::Run.find(params[:id])

  def require_every_member
    missing = Consolidation::Access.missing(current_user, @run.group)
    redirect_to accounting_consolidation_groups_path, alert: "You do not have access to every company of this group (#{missing} missing): a consolidation is refused whole, never partial." if missing.positive?
  end

  def audit(action, **payload) = Accounting::AuditLog.record!(auditable: @run, action: action, user: current_user, payload: { group: @run.group.name, reporting_date: @run.reporting_date.iso8601 }.merge(payload))

  # The lines a person starts from when asked for an adjustment about a pair of headings (an elimination of the difference, to be reviewed and justified).
  def prefilled(entry)
    context = entry.context
    return unless context["heading_creditor"] && params[:amount].present?

    statements = Consolidation::Intragroup.statements_of(context["kind"])
    amount = params[:amount]
    if context["kind"] == "balances"
      entry.lines.build(statement: "liabilities", code: context["heading_debtor"], side: "debit", amount: amount)
      entry.lines.build(statement: "assets", code: context["heading_creditor"], side: "credit", amount: amount)
    else
      entry.lines.build(statement: statements.first, code: context["heading_creditor"], side: "debit", amount: amount)
      entry.lines.build(statement: statements.last, code: context["heading_debtor"], side: "credit", amount: amount)
    end
  end

  def export_rows(view)
    row = Struct.new(:section, :code, :label, :amount, keyword_init: true)
    rows = view.members.map { |m| row.new(section: "Perimeter", code: m["method"], label: "#{m['name']} (#{m['stake']} %, #{m['currency']})", amount: m["stake"]) }
    rows += view.entries.flat_map { |e| e["lines"].map { |l| row.new(section: "Eliminations", code: "#{l['statement']}/#{l['code']}", label: "#{e['comment']} (#{l['side']})", amount: l["amount"]) } }
    rows += view.statements.flat_map { |statement, list| list.map { |r| row.new(section: statement.humanize, code: r["code"], label: r["label"], amount: r["amount"]) } }
    rows << row.new(section: "Fingerprint", code: "SHA-256", label: @run.snapshot_sha256 || "not frozen", amount: nil)
    rows << row.new(section: "Status", code: @run.status, label: @run.provisional ? "PROVISIONAL: a member's year is open or ends another day" : "Final", amount: nil)
  end
end
