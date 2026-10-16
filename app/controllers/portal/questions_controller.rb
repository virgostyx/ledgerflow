# B02c: the questions of the firm, and the answers. A question is read through the scope of the person's right; the answer is typed, cleaned and kept once. The firm's side turns it into a comment
# of its task: the portal changes nothing in the books.
class Portal::QuestionsController < Portal::BaseController
  def index
    @questions = Portal::Question.in_reach_of(current_portal_user).open.order(:due_on, :asked_at).includes(:company)
  end

  def show
    @question = find_open or return
    @files = Portal::Upload.of(current_portal_user).where(question_id: @question.id)
  end

  def answer
    question = Portal::Question.in_reach_of(current_portal_user).find_by(token: params[:token])
    return not_in_scope(params[:token]) unless question
    return redirect_to(questions_path, alert: t("portal.questions.already"), status: :see_other) unless question.open?

    value = typed_value(question)
    return redirect_to(question_path(question), alert: t("portal.questions.invalid"), status: :see_other).tap { response.status = 422 } unless value

    Portal::Answer.transaction do
      Portal::Answer.create!(question: question, portal_user: current_portal_user, entity_id: question.entity_id, body: Portal::Answer.clean(params[:body]).presence, value: value, answered_at: Time.current)
      question.update!(status: "answered")
    end
    record_event("question_answered", entity_id: question.entity_id, target_token: question.token, answer_type: question.answer_type)
    redirect_to questions_path, notice: t("portal.questions.answered")
  rescue ActiveRecord::RecordNotUnique
    redirect_to questions_path, alert: t("portal.questions.already"), status: :see_other
  end

  private

  def find_open
    question = Portal::Question.in_reach_of(current_portal_user).find_by(token: params[:token])
    return not_in_scope(params[:token]) && nil unless question
    return redirect_to(questions_path, alert: t("portal.questions.expired")) && nil unless question.open?

    question
  end

  # The typed value of the answer, or nil when it is not valid for the type of the question.
  def typed_value(question)
    case question.answer_type
    when "text" then Portal::Answer.clean(params[:body]).present? ? {} : nil
    when "single" then (key = params[:choice].to_s; question.choice_keys.include?(key) ? { "choices" => [ key ] } : nil)
    when "multiple" then (keys = Array(params[:choices]).map(&:to_s).uniq; keys.any? && (keys - question.choice_keys).empty? ? { "choices" => keys } : nil)
    when "yes_no" then %w[yes no].include?(params[:yes_no].to_s) ? { "yes_no" => params[:yes_no] == "yes" } : nil
    when "amount" then (amount = BigDecimal(params[:amount].to_s.tr(",", "."), exception: false); amount && amount.finite? && amount.abs < 10**13 && amount.scale <= 2 ? { "amount" => amount.to_s("F") } : nil)
    when "date" then (date = Date.iso8601(params[:date].to_s) rescue nil; date ? { "date" => date.iso8601 } : nil)
    when "file" then Portal::Upload.of(current_portal_user).where(question_id: question.id).exists? ? {} : nil
    end
  end
end
