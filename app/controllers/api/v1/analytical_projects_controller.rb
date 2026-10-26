# Idempotent upsert of the analytical accounts of a project and its budget lines, keyed by the caller's own reference
# (docs/dev/api/inbound-api.md). The work is Accounting::ExternalAnalytics.
class Api::V1::AnalyticalProjectsController < Api::V1::BaseController
  self.action_scopes = { update: "analytical:write" }

  STATUSES = { created: :created, ok: :ok, unprocessable: :unprocessable_content, conflict: :conflict }.freeze

  def update
    result = Accounting::ExternalAnalytics.upsert(params[:external_ref], params.permit(:code, :name, :active, budget_lines: %i[ref code label]))

    case result.status
    when :created, :ok then render json: serialize(result), status: STATUSES.fetch(result.status)
    when :conflict     then render json: { error: result.errors.values.flatten.first }, status: :conflict
    else                    render json: { errors: result.errors }, status: :unprocessable_content
    end
  end

  private

  def serialize(result)
    { ref: result.project.external_ref, code: result.project.code, active: result.project.active,
      budget_lines: result.budget_lines.map { |l| { ref: l.external_ref, code: l.code, active: l.active } } }
  end
end
