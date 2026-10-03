# F02: the CODA statements: import a file, see what came in (balances, "to review", breaks in the chain), open a statement.
class Accounting::BankStatementsController < ApplicationController
  before_action { require_feature!(:f02) }

  def index
    authorize Accounting::BankStatement
    @pagy, @statements = pagy(Accounting::BankStatement.includes(:bank_account, :import_batch).order(Arel.sql("COALESCE(new_balance_date, old_balance_date) DESC"), id: :desc))
    @refused = Accounting::ImportBatch.where(result: "rejected").order(id: :desc).limit(5)
  end

  def show
    @statement = Accounting::BankStatement.includes(:bank_account, :import_batch).find(params[:id])
    authorize @statement
    @transactions = @statement.transactions.order(:id)
  end

  def new
    authorize Accounting::BankStatement, :import?
  end

  def create
    authorize Accounting::BankStatement, :import?
    file = params[:file]
    return render_new(Banking::ImportStatements::NO_FILE) unless file.respond_to?(:read)

    result = Banking::ImportStatements.call(bytes: file.read, user: current_user, source_name: file.original_filename)
    return render_new(result) if result.failure?

    flash[:notice] = t("banking.import.done", imported: result[:imported], skipped: result[:skipped], drafted: result[:drafted], suggested: result[:suggested])
    flash[:alert] = result[:warnings].join(" ") if result[:warnings].any?
    redirect_to accounting_bank_statements_path
  end

  private

  def render_new(result)
    @result = result
    render :new, status: :unprocessable_content
  end
end
