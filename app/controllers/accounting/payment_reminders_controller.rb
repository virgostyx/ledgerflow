class Accounting::PaymentRemindersController < ApplicationController
  # F09 replaces the manual reminders: same open lines, same follow-up, with levels, texts and a validation. The old reminders stay on their invoices.
  before_action { redirect_to accounting_dunning_runs_path if feature?(:f09) }

  def index
    authorize Accounting::PaymentReminder
    @rows = Accounting::OverdueReminders.call
  end

  def create
    authorize Accounting::PaymentReminder

    partners = Accounting::Partner.includes(:entity).where(id: Array(params[:partner_ids]))
    return redirect_to(accounting_payment_reminders_path, alert: t("accounting.payment_reminders.errors.none_selected")) if partners.empty?

    failures = partners.filter_map do |partner|
      result = Accounting::SendPaymentReminder.call(partner: partner, recipient: params.dig(:recipients, partner.id.to_s), user: current_user)
      "#{partner.name}: #{result.message}" if result.failure?
    end

    flash[:notice] = t("accounting.payment_reminders.created", count: partners.size - failures.size) if failures.size < partners.size
    flash[:alert]  = failures.join(" ") if failures.any?
    redirect_to accounting_payment_reminders_path
  end
end
