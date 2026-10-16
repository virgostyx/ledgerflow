# B02c: the questions of the firm to the people of the portal: ask (from a bank line, a document or an entry, or from a template), follow the answers, close.
class Accounting::PortalQuestionsController < ApplicationController
  before_action -> { require_feature!(:b02c) }
  before_action -> { authorize Accounting::PortalAccessPolicy, "#{action_name == 'new' ? 'index' : action_name == 'close' ? 'index' : action_name}?".to_sym, policy_class: Accounting::PortalAccessPolicy }

  TARGETS = %w[Accounting::BankTransaction Accounting::Document Accounting::JournalEntry].freeze

  def index
    @questions = Portal::Question.where(entity_id: entity.id).includes(:answer).order(asked_at: :desc).limit(200)
    @suggestions = Accounting::QuestionSuggestion.where(portal_question_id: @questions.map(&:id)).group_by(&:portal_question_id)
  end

  def new
    @target = target
    @prefill = PortalAdmin::QuestionTemplates.keys.include?(params[:template]) ? PortalAdmin::QuestionTemplates.fetch(params[:template], params[:language].presence || "en") : {}
  end

  def create
    return redirect_to(accounting_portal_questions_path, alert: "The thing you ask about was not found.") if params[:target_id].present? && target.nil?

    result = PortalAdmin::AskQuestion.call(entity: entity, by: current_user, title: params[:title], answer_type: params[:answer_type], target: target, due_on: params[:due_on], choices: parse_choices(params[:choices]))
    if result.success?
      redirect_to accounting_portal_questions_path, notice: "Asked. The clients who may answer are told."
    else
      redirect_to accounting_portal_questions_path, alert: result.message
    end
  end

  def close
    question = Portal::Question.where(entity_id: entity.id).find_by!(token: params[:id])
    question.update!(status: "closed") if question.open?
    Accounting::AuditLog.record!(auditable: Accounting::Task.find_by(id: question.task_id) || entity, action: "portal_question_closed", user: current_user, payload: { question: question.token })
    redirect_to accounting_portal_questions_path, notice: "Closed."
  end

  private

  def entity = ActsAsTenant.current_tenant

  # The thing asked about: of this company (the tenant scope), of a kind the client may be asked about.
  def target
    return unless TARGETS.include?(params[:target_type]) && params[:target_id].present?

    params[:target_type].constantize.find_by(id: params[:target_id])
  end

  # One choice per line: key|label or key|label|suggested treatment.
  def parse_choices(text)
    text.to_s.lines.filter_map do |line|
      key, label, treatment = line.strip.split("|", 3).map(&:strip)
      { key: key, label: label, suggested_treatment: treatment.presence } if key.present? && label.present?
    end
  end
end
