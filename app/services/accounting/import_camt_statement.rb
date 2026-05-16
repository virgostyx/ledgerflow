class Accounting::ImportCamtStatement
  extend LightService::Organizer

  NS = "urn:iso:std:iso:20022:tech:xsd:camt.053.001.02"

  def self.call(xml:, bank_account:)
    entries = parse_entries(xml)
    imported = 0

    ApplicationRecord.transaction do
      entries.each do |entry|
        next if Accounting::BankTransaction.exists?(
          bank_account: bank_account,
          reference:    entry[:reference]
        )

        Accounting::BankTransaction.create!(
          bank_account:     bank_account,
          transaction_date: entry[:transaction_date],
          value_date:       entry[:value_date],
          amount:           entry[:amount],
          currency:         entry[:currency],
          description:      entry[:description],
          reference:        entry[:reference],
          raw_data:         entry
        )
        imported += 1
      end
    end

    ctx = LightService::Context.make(imported_count: imported)
    ctx
  rescue StandardError => e
    ctx = LightService::Context.make(imported_count: 0)
    ctx.fail!("Import error: #{e.message}")
    ctx
  end

  def self.parse_entries(xml)
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!

    doc.xpath("//Ntry").map do |ntry|
      raw_amount = BigDecimal(ntry.at_xpath("Amt")&.text || "0")
      direction  = ntry.at_xpath("CdtDbtInd")&.text
      amount     = direction == "DBIT" ? -raw_amount : raw_amount
      currency   = ntry.at_xpath("Amt/@Ccy")&.value || "EUR"
      booked     = ntry.at_xpath("BookgDt/Dt")&.text
      value      = ntry.at_xpath("ValDt/Dt")&.text
      ref        = ntry.at_xpath("NtryDtls/TxDtls/Refs/EndToEndId")&.text
      descr      = ntry.at_xpath("NtryDtls/TxDtls/RmtInf/Ustrd")&.text

      {
        transaction_date: booked ? Date.parse(booked) : Date.current,
        value_date:       value  ? Date.parse(value)  : nil,
        amount:           amount,
        currency:         currency,
        description:      descr,
        reference:        ref
      }
    end
  end
  private_class_method :parse_entries
end
