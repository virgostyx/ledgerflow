# Checks, before anything is built or sent, that this invoice can go through the Peppol network from this entity, and
# finds who sends and who receives. Fails with a message the user can act on.
class Peppol::Actions::ValidateSendable
  extend LightService::Action

  expects  :invoice
  promises :access_point, :sender, :receiver

  executed do |ctx|
    invoice = ctx.invoice
    entity  = invoice.entity
    error   = sendability_error(invoice)
    next ctx.fail!(error) if error

    access_point = Peppol::AccessPoint.for(entity)
    sender = entity.peppol_participant_id
    next ctx.fail!(I18n.t("peppol.errors.no_sender_id")) if sender.blank?
    next ctx.fail!(I18n.t("peppol.errors.no_vat_number")) if entity.vat_number.blank? && invoice.lines.any? { |l| l.vat_rate.to_d.positive? }

    receiver = invoice.partner.peppol_participant_id_or_default
    next ctx.fail!(I18n.t("peppol.errors.no_receiver_id", partner: invoice.partner.name)) if receiver.blank?
    if access_point.class.requires_buyer_email? && invoice.partner.email.blank?
      next ctx.fail!(I18n.t("peppol.errors.no_buyer_email", partner: invoice.partner.name))
    end
    next ctx.fail!(I18n.t("peppol.errors.not_registered", receiver: receiver)) if access_point.registered?(receiver) == false

    ctx.access_point = access_point
    ctx.sender       = sender
    ctx.receiver     = receiver
  rescue Peppol::AccessPoint::NotConfigured => e
    ctx.fail!(e.message)
  end

  def self.sendability_error(invoice)
    return I18n.t("peppol.errors.not_customer") unless invoice.customer?
    return I18n.t("peppol.errors.invoice_not_posted") unless invoice.issued?

    I18n.t("peppol.errors.already_sent", status: invoice.peppol_status) if invoice.queued? || invoice.delivered?
  end
  private_class_method :sendability_error
end
