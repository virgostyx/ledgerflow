class Payments::Actions::BuildSepaXml
  extend LightService::Action

  expects :payment_batch
  promises :sepa_xml, :message_id

  executed do |ctx|
    batch       = ctx.payment_batch
    bank_account = batch.bank_account
    # pain.001 MsgId is capped at 35 chars by the ISO 20022 schema, so a
    # dash-free UUID (32 hex chars) is used instead of SecureRandom.uuid.
    message_id = SecureRandom.uuid.delete("-")

    credit_transfer = SEPA::CreditTransfer.new(
      name: batch.entity.legal_name,
      iban: bank_account.iban,
      bic:  bank_account.bic
    )
    credit_transfer.message_identification = message_id

    batch.lines.includes(invoice: :partner).each do |line|
      partner = line.invoice.partner
      credit_transfer.add_transaction(
        name: partner.name,
        iban: partner.iban,
        bic: partner.bic.presence,
        amount: line.amount,
        reference: line.invoice.invoice_number.to_s.truncate(35),
        remittance_information: line.remittance_information,
        requested_date: batch.requested_execution_date
      )
    end

    ctx.sepa_xml   = credit_transfer.to_xml(SEPA::PAIN_001_001_03)
    ctx.message_id = message_id
  rescue SEPA::Error, ArgumentError => e
    ctx.fail!(I18n.t("payments.errors.sepa_generation_failed", message: e.message))
  end
end
