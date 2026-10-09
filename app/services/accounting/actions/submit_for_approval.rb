# B01a: a purchase invoice that has just been posted goes to approval, or is recorded as needing none. The accounting is done
# whatever happens here: a failure to submit never undoes the posting (the invoice can be submitted again by hand).
class Accounting::Actions::SubmitForApproval
  extend LightService::Action

  expects :invoice

  executed do |ctx|
    invoice = ctx.invoice
    next unless invoice.supplier? && invoice.entity.feature?(:b01a)

    result = Approvals::Submit.call(invoice: invoice, user: Current.user)
    Rails.logger.warn("[approvals] invoice #{invoice.id} not submitted: #{result.message}") if result.failure?
  end
end
