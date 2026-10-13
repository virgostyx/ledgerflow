# B01b: how each bank takes its payment file - the version of the format, the limits of a file, the days the bank does not settle. The version comes from the bank
# (its documentation, or a file it was seen to take), never from a guess: only the versions the builder knows are offered. Closed while the feature is off.
class Accounting::Settings::PaymentBankProfilesController < Accounting::Settings::BaseController
  before_action { require_feature!(:b01b) }
  before_action :set_profile, only: %i[edit update]

  def index
    @profiles = Payments::BankProfile.order(:name)
  end

  def new
    @profile = Payments::BankProfile.new(format_version: Payments::Sepa::Pain001Builder::VERSIONS.first)
  end

  def create
    @profile = Payments::BankProfile.new
    save(:new, t("payments.profiles.created"))
  end

  def edit; end

  def update
    save(:edit, t("payments.profiles.updated"))
  end

  private

  def set_profile = (@profile = Payments::BankProfile.find(params[:id]))

  def save(template, notice)
    @profile.assign_attributes(profile_attributes)
    # Only a version the builder knows is recorded from here: a profile that named another one could never give a file.
    @profile.errors.add(:format_version, "is not one this application can make (#{Payments::Sepa::Pain001Builder::VERSIONS.join(', ')})") unless Payments::Sepa::Pain001Builder::VERSIONS.include?(@profile.format_version)
    if @profile.errors.empty? && @profile.valid? && @profile.save
      redirect_to accounting_settings_payment_bank_profiles_path, notice: notice
    else
      flash.now[:alert] = @profile.errors.full_messages.to_sentence
      render template, status: :unprocessable_content
    end
  rescue ArgumentError => e
    flash.now[:alert] = e.message
    render template, status: :unprocessable_content
  end

  def profile_attributes
    raw = params.require(:payment_bank_profile).permit(:name, :format_version, :max_payments, :max_batch_total, :max_supplier_total, :balance_threshold, :closed_days, :format_verified, :coda_verified)
    attrs = raw.to_h.symbolize_keys.except(:closed_days)
    attrs[:balance_threshold] = 0 if attrs.key?(:balance_threshold) && attrs[:balance_threshold].blank?
    attrs[:options] = (@profile.options || {}).merge("closed_days" => closed_days(raw[:closed_days])) if raw.key?(:closed_days)
    attrs
  end

  def closed_days(text)
    text.to_s.split(/[,\s]+/).compact_blank.map { |day| Date.iso8601(day).iso8601 }.sort.uniq
  rescue Date::Error
    raise ArgumentError, t("payments.profiles.bad_date")
  end
end
