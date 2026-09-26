# Builds an XML representation of a periodic VAT declaration, shaped after the publicly
# documented Intervat "VATConsignment" structure (FPS Finance). This has not been validated
# against the current official XSD — verify it before any real submission to Intervat.
class Accounting::BuildIntervatXml
  NAMESPACE        = "http://www.minfin.fgov.be/VATConsignment"
  COMMON_NAMESPACE = "http://www.minfin.fgov.be/InputCommon"

  def initialize(declaration)
    @declaration = declaration
    @entity      = declaration.entity
  end

  def build
    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.VATConsignment("xmlns" => NAMESPACE, "xmlns:common" => COMMON_NAMESPACE, "VATDeclarationsNbr" => "1") do
        xml.VATDeclaration("SequenceNumber" => "1") do
          xml.Declarant do
            xml["common"].VATNumber vat_number # the Declarant children belong to the common namespace
            xml["common"].Name @entity.legal_name
          end
          xml.Period do
            build_period(xml)
          end
          xml.Data do
            grids.each { |code, amount| xml.Amount amount, GridNumber: code }
          end
          # ponytail: the client listing is filed apart and no payment form / refund is requested;
          # change these answers when the user needs them.
          xml.ClientListingNihil "NO"
          xml.Ask("Restitution" => "NO", "Payment" => "NO")
        end
      end
    end

    builder.to_xml
  end

  private

  def vat_number
    @entity.vat_number.to_s.sub(/\A[A-Z]{2}/, "")
  end

  def build_period(xml)
    if @declaration.monthly?
      xml.Month @declaration.period_start.month
    else
      xml.Quarter ((@declaration.period_start.month - 1) / 3) + 1
    end
    xml.Year @declaration.period_start.year
  end

  # Amounts are non-negative in the schema: a grid pushed below zero by credit notes is reported
  # as 0.00 (notice n° 163; the carry-over to the next period is not implemented).
  def grids
    @declaration.grids.map { |code, amount| [ code.to_i, format("%.2f", [ BigDecimal(amount), 0 ].max) ] }.sort
  end
end
