# B02c: the client's dashboard. It reads only the latest published snapshot (Portal::Snapshot) of the companies where a right in force lists dashboard.view: the books, the reports and every
# calculation stay on the firm's side. It names no third party.
class Portal::DashboardsController < Portal::BaseController
  helper_method :money

  def show
    @companies = companies.order(:name).to_a
    @companies = @companies.select { |company| company.id == params[:company].to_i } if params[:company].present?
    return not_in_scope(params[:company]) if params[:company].present? && @companies.empty?

    @snapshots = @companies.index_with { |company| Portal::Snapshot.latest_for(company.id) }
    respond_to do |format|
      format.html
      format.pdf { send_data Portal::DashboardPdf.call(@snapshots.compact_blank, labels: pdf_labels), filename: "dashboard.pdf", type: "application/pdf", disposition: "attachment" }
    end
  end

  private

  def companies
    Portal::Company.where(questions_enabled: true, id: current_portal_user.open_grants.where("portal_grants.capabilities @> ?", [ "dashboard.view" ].to_json).select(:entity_id))
  end

  # An amount written for the person's language (a string with two decimals goes in, a string comes out: never a Float).
  def money(text)
    whole, fraction = text.to_s.split(".")
    sign = whole.start_with?("-") ? "-" : ""
    digits = whole.delete("-")
    group, decimal = I18n.locale == :en ? [ ",", "." ] : (I18n.locale == :nl ? [ ".", "," ] : [ " ", "," ])
    "#{sign}#{digits.reverse.scan(/\d{1,3}/).join(group).reverse}#{decimal}#{fraction.to_s.ljust(2, '0')}"
  end

  def pdf_labels
    Portal::Snapshot::INDICATORS.index_with { |key| t("portal.dashboard.indicators.#{key}.title") }.merge("title" => t("portal.dashboard.title"), "updated" => t("portal.dashboard.updated", date: "%{date}"),
                                                                                                          "provisional" => t("portal.dashboard.provisional"), "word" => t("portal.dashboard.word"))
  end
end
