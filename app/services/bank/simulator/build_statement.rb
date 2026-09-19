# Builds a CAMT.053 statement from plain hashes, to feed Accounting::ImportCamtStatement.
# Amounts are signed (credit +, debit -). Pure function: no DB access.
# ponytail: no XSD validation; round-trip with our own parser is the only conformance check.
class Bank::Simulator::BuildStatement
  NS = "urn:iso:std:iso:20022:tech:xsd:camt.053.001.02"

  def self.call(iban:, entries:)
    Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.Document(xmlns: NS) do
        xml.BkToCstmrStmt do
          xml.Stmt do
            xml.Acct { xml.Id { xml.IBAN iban } }
            entries.each { |entry| build_entry(xml, entry) }
          end
        end
      end
    end.to_xml
  end

  def self.build_entry(xml, entry)
    amount = BigDecimal(entry.fetch(:amount).to_s)
    raise ArgumentError, "amount must not be zero" if amount.zero?

    date      = entry.fetch(:date)
    credit    = amount.positive?
    reference = entry[:reference].presence || SecureRandom.hex(8)
    party     = credit ? :Dbtr : :Cdtr

    xml.Ntry do
      xml.Amt format("%.2f", amount.abs), Ccy: "EUR"
      xml.CdtDbtInd credit ? "CRDT" : "DBIT"
      xml.BookgDt { xml.Dt date.iso8601 }
      xml.ValDt { xml.Dt (entry[:value_date] || date).iso8601 }
      xml.NtryDtls do
        xml.TxDtls do
          xml.Refs { xml.EndToEndId reference }
          if entry[:counterparty_name] || entry[:counterparty_iban]
            xml.RltdPties do
              xml.send(party) { xml.Nm entry[:counterparty_name] } if entry[:counterparty_name]
              xml.send(:"#{party}Acct") { xml.Id { xml.IBAN entry[:counterparty_iban] } } if entry[:counterparty_iban]
            end
          end
          xml.RmtInf { xml.Ustrd entry[:description] } if entry[:description]
        end
      end
    end
  end
  private_class_method :build_entry
end
