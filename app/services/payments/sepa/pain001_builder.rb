# The payment file of a batch (B01b §5 "Génération du fichier"): a pain.001 credit transfer, serialized by sepa_king and validated by it against the XSD of its version.
# The same batch at the same moment gives the same bytes: nothing here reads the clock or draws a number (the moment is given, the message id is the reference of the batch,
# the order of the payments is that of their creation), so the file kept at the export can be made again and compared.
# The version of the format comes from the bank profile of the batch, never from a guess: one this builder does not know is refused.
# ponytail: a structured communication is written in its printed form (+++090/9337/55493+++) in the free text field; the structured field (Strd) waits for a bank that documents it.
module Payments::Sepa
  class UnsupportedVersion < StandardError; end

  class Pain001Builder
    VERSIONS = [ SEPA::PAIN_001_001_03 ].freeze

    def self.call(batch, created_at:) = new(batch, created_at).call

    def initialize(batch, created_at)
      @batch = batch
      @created_at = created_at
    end

    def call
      version = @batch.bank_profile&.format_version
      raise UnsupportedVersion, "No bank profile: the format of the file comes from the bank." unless version
      raise UnsupportedVersion, "The version #{version} is not one this builder knows (#{VERSIONS.join(', ')})." unless VERSIONS.include?(version)

      transfer = SEPA::CreditTransfer.new(name: text(@batch.entity.legal_name, 70), iban: @batch.bank_account.iban, bic: @batch.bank_account.bic.presence)
      transfer.message_identification = @batch.message_id.presence || @batch.reference
      transfer.creation_date_time = @created_at.in_time_zone.strftime("%Y-%m-%dT%H:%M:%S")
      items.each { |item| add(transfer, item) }
      transfer.to_xml(version)
    end

    private

    def items = @batch.items.where(status: :included).order(:id)

    def add(transfer, item)
      transfer.add_transaction(name: text(item.holder_name, 70), iban: item.iban, bic: item.bic.presence, amount: item.amount, reference: item.end_to_end_id,
                               remittance_information: remittance(item), requested_date: @batch.requested_execution_date)
    end

    def remittance(item)
      return Accounting::StructuredCommunication.display(item.remittance) if item.structured_remittance && item.remittance.to_s.match?(/\A\d{12}\z/)

      text(item.remittance, 140).presence
    end

    def text(value, max) = Payments::SepaText.clean(value, max: max)
  end
end
