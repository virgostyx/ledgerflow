class Accounting::Settings::JournalsController < Accounting::Settings::BaseController
  before_action :set_journal,   only: [ :edit, :update, :destroy, :toggle_active ]
  before_action :load_accounts, only: [ :new, :create, :edit, :update ]

  def index
    @journals = Accounting::Journal.includes(:default_account).order(:journal_type, :code)
  end

  def new
    @journal = Accounting::Journal.new
  end

  def create
    @journal = Accounting::Journal.new(journal_params)
    if @journal.save
      redirect_to accounting_settings_journals_path,
                  notice: t("accounting.settings.journals.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @journal.update(journal_params)
      redirect_to accounting_settings_journals_path,
                  notice: t("accounting.settings.journals.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @journal.destroyable?
      @journal.destroy!
      redirect_to accounting_settings_journals_path,
                  notice: t("accounting.settings.journals.deleted")
    else
      redirect_to accounting_settings_journals_path,
                  alert: t("accounting.settings.journals.not_destroyable")
    end
  end

  def toggle_active
    if @journal.active? && !@journal.deactivatable?
      redirect_to accounting_settings_journals_path,
                  alert: t("accounting.settings.journals.not_deactivatable")
    else
      @journal.update!(active: !@journal.active?)
      redirect_to accounting_settings_journals_path,
                  notice: t("accounting.settings.journals.toggled")
    end
  end

  private

  def set_journal
    @journal = Accounting::Journal.find(params[:id])
  end

  def load_accounts
    @accounts = Accounting::Account.where(active: true, is_leaf: true).order(:code)
  end

  def journal_params
    params.require(:accounting_journal).permit(
      :code, :label_fr, :journal_type, :sequence_prefix, :default_account_id, :active
    )
  end
end
