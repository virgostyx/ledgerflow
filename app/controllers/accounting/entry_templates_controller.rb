# F07: entry templates, and the draft entry made from one.
class Accounting::EntryTemplatesController < ApplicationController
  before_action :set_template, only: %i[edit update destroy entry create_entry]
  before_action -> { authorize Accounting::EntryTemplate, :index? }

  def index
    @templates = Accounting::EntryTemplate.includes(:journal, lines: :account).order(:name)
  end

  def new
    @template = Accounting::EntryTemplate.new
    4.times { |i| @template.lines.build(position: i) }
  end

  def create
    @template = Accounting::EntryTemplate.new(template_params)
    if @template.save
      redirect_to accounting_entry_templates_path, notice: "Template #{@template.name} created"
    else
      (4 - @template.lines.size).times { @template.lines.build }
      render :new, status: :unprocessable_content
    end
  end

  def edit
    2.times { @template.lines.build(position: @template.lines.size) }
  end

  def update
    if @template.update(template_params)
      redirect_to accounting_entry_templates_path, notice: "Template #{@template.name} updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @template.destroy
      redirect_to accounting_entry_templates_path, notice: "Template #{@template.name} deleted"
    else
      redirect_to accounting_entry_templates_path, alert: @template.errors.full_messages.to_sentence
    end
  end

  def examples
    added = Accounting::SeedEntryTemplates.call
    redirect_to accounting_entry_templates_path, notice: "#{added} example template(s) added"
  end

  # The date, and the amounts the template asks for.
  def entry; end

  def create_entry
    result = Accounting::BuildEntryFromTemplate.call(template: @template, date: params[:date].presence && Date.parse(params[:date]),
                                                     base_amount: params[:base_amount].presence, inputs: params[:inputs]&.to_unsafe_h, user: current_user)
    if result.success?
      redirect_to accounting_journal_entry_path(result[:entry]), notice: "Draft created from the template #{@template.name}: check it, then post it"
    else
      flash.now[:alert] = result.message
      render :entry, status: :unprocessable_content
    end
  rescue Date::Error
    flash.now[:alert] = "Enter a valid date"
    render :entry, status: :unprocessable_content
  end

  private

  def set_template = @template = Accounting::EntryTemplate.includes(lines: %i[account partner]).find(params[:id])

  def template_params
    params.require(:accounting_entry_template).permit(:name, :journal_id, :description,
      lines_attributes: %i[id account_id partner_id side amount_kind amount percentage vat_code label position _destroy])
  end
end
