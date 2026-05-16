class Accounting::VatDeclarationsController < ApplicationController
  before_action :set_declaration, only: [ :show ]

  def index
    @declarations = policy_scope(Accounting::VatDeclaration).order(period_start: :desc)
  end

  def show
    authorize @declaration
  end

  def new
    @declaration = Accounting::VatDeclaration.new
    @fiscal_years = Accounting::FiscalYear.all.order(start_date: :desc)
    authorize @declaration
  end

  def create
    authorize Accounting::VatDeclaration.new

    result = Accounting::GenerateVatReturn.call(
      fiscal_year_id: declaration_params[:fiscal_year_id].to_i,
      period_start:   Date.parse(declaration_params[:period_start]),
      period_end:     Date.parse(declaration_params[:period_end]),
      period_type:    declaration_params[:period_type]
    )

    if result.success?
      redirect_to accounting_vat_declaration_path(result[:vat_declaration]),
                  notice: t("accounting.vat_declarations.created")
    else
      @declaration = Accounting::VatDeclaration.new(declaration_params)
      @fiscal_years = Accounting::FiscalYear.all.order(start_date: :desc)
      flash.now[:alert] = result.message
      render :new, status: :unprocessable_content
    end
  rescue ArgumentError, TypeError
    @declaration = Accounting::VatDeclaration.new(declaration_params)
    @fiscal_years = Accounting::FiscalYear.all.order(start_date: :desc)
    render :new, status: :unprocessable_content
  end

  private

  def set_declaration
    @declaration = Accounting::VatDeclaration.find(params[:id])
  end

  def declaration_params
    params.require(:accounting_vat_declaration).permit(
      :fiscal_year_id, :period_type, :period_start, :period_end
    )
  end
end
