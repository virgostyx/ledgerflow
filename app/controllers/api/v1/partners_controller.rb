# Idempotent upsert of a partner keyed by the caller's own reference (docs/dev/api/inbound-api.md).
# An unlinked partner with the same VAT number is adopted rather than duplicated; one already linked
# to another reference is a conflict.
class Api::V1::PartnersController < Api::V1::BaseController
  self.action_scopes = { update: "partners:write" }

  FIELDS = %i[name partner_type vat_number email phone street city zip country iban bic
              payment_terms_days peppol_participant_id active notes].freeze

  def update
    partner = find_partner
    return render(json: { error: "VAT number belongs to another external_ref" }, status: :conflict) if partner == :conflict

    created = partner.nil?
    partner ||= Accounting::Partner.new
    partner.assign_attributes(partner_attributes.merge(external_ref: params[:external_ref]))

    if partner.save
      render json: serialize(partner), status: created ? :created : :ok
    else
      render json: { errors: partner.errors.to_hash }, status: :unprocessable_content
    end
  rescue ArgumentError => e # unknown enum value
    render json: { errors: { partner_type: [ e.message ] } }, status: :unprocessable_content
  rescue ActiveRecord::RecordNotUnique
    render json: { error: "Concurrent update, retry" }, status: :conflict
  end

  private

  def find_partner
    linked = Accounting::Partner.find_by(external_ref: params[:external_ref])
    return linked if linked

    vat = params[:vat_number].presence or return nil
    same_vat = Accounting::Partner.find_by(vat_number: vat)
    return nil unless same_vat

    same_vat.external_ref.nil? ? same_vat : :conflict
  end

  def partner_attributes = params.permit(*FIELDS).to_h

  def serialize(partner)
    partner.slice(:id, :external_ref, :name, :partner_type, :vat_number, :country, :active)
  end
end
