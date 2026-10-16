# B02b: the client says why there is no document for a line. The answer is kept as it is; the firm's side turns it into a task. Nothing is booked.
class Portal::DocumentRequestLinesController < Portal::BaseController
  def answer
    line = Portal::DocumentRequestLine.in_reach_of(current_portal_user, capability: "questions.answer").open_ones.find_by(token: params[:token])
    return not_in_scope(params[:token]) unless line

    reason = params[:reason].to_s
    note = params[:note].to_s.strip.first(300)
    unless Portal::DocumentRequestLine::REASONS.key?(reason) && (reason != "other" || note.present?)
      return redirect_to(document_requests_path, alert: "Choose a reason (and write a note for \"Other\").", status: :see_other).tap { response.status = 422 }
    end

    line.update!(state: "explained", answer_reason: reason, answer_note: note.presence, answered_by: current_portal_user, answered_at: Time.current)
    record_event("document_request_answered", entity_id: line.entity_id, target_token: line.token, reason: reason)
    redirect_to document_requests_path, notice: "Thank you. Your accountant will take it from here."
  end
end
