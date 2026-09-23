# Builds an XML representation of a periodic VAT declaration, shaped after the publicly
# documented Intervat "VATConsignment" structure (FPS Finance). This has not been validated
# against the current official XSD — verify it before any real submission to Intervat.
class Accounting::BuildIntervatXml
  NAMESPACE = "http://www.minfin.fgov.be/VATConsignment"

  def initialize(declaration)
    @declaration = declaration
    @entity      = declaration.entity
  end

  def build
    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      xml.VATConsignment("xmlns" => NAMESPACE, "VATDeclarationsNbr" => "1") do
        xml.VATDeclarationDeclarantSequence do
          xml.Sequence "1"
          xml.VATDeclarantIdentity do
            xml.VATNumber vat_number
            xml.Name @entity.legal_name
          end
          xml.VATDeclaration("SequenceNumber" => "1") do
            xml.Period period_code
            xml.Data do
              @declaration.grids.sort.each do |code, amount|
                xml.Amount amount, GridNumber: code
              end
            end
          end
        end
      end
    end

    builder.to_xml
  end

  private

  def vat_number
    @entity.vat_number.to_s.sub(/\A[A-Z]{2}/, "")
  end

  def period_code
    return @declaration.period_start.strftime("%Y-%m") if @declaration.monthly?
    quarter = ((@declaration.period_start.month - 1) / 3) + 1
    "#{@declaration.period_start.year}Q#{quarter}"
  end
end
