# F03: attaching a document to what it justifies, and detaching it.
class Accounting::DocumentLinksController < ApplicationController
  before_action { require_feature!(:f03) }

  # Only these kinds of target, found through the current entity (another entity's record does not exist here).
  TARGETS = { "entry" => Accounting::JournalEntry, "partner" => Accounting::Partner, "fixed_asset" => Accounting::FixedAsset,
              "invoice" => Accounting::Invoice, "bank_transaction" => Accounting::BankTransaction }.freeze

  def create
    document = Accounting::Document.find(params[:document_id])
    authorize document, :link?
    target = find_target
    return redirect_to(accounting_document_path(document), alert: t("documents.errors.no_such_target")) unless target

    result = Accounting::LinkDocument.call(document: document, target: target, user: current_user)
    flash[result.success? ? :notice : :alert] = result.success? ? t("documents.linked") : result.message
    back_to_entry = target.is_a?(Accounting::JournalEntry) && params[:entry_reference].blank?
    redirect_to(back_to_entry ? accounting_journal_entry_path(target) : accounting_document_path(document))
  end

  def destroy
    link = Accounting::DocumentLink.where(document_id: Accounting::Document.select(:id)).find(params[:id])
    authorize link.document, :unlink?
    result = Accounting::UnlinkDocument.call(link: link, user: current_user)
    flash[result.success? ? :notice : :alert] = result.success? ? t("documents.unlinked") : result.message
    redirect_to accounting_document_path(link.document)
  end

  private

  def find_target
    return Accounting::JournalEntry.find_by(reference: params[:entry_reference].to_s.strip) if params[:entry_reference].present?

    klass = TARGETS[params[:target_type]]
    raise ActiveRecord::RecordNotFound, "unknown target" unless klass

    klass.find(params[:target_id])
  end
end
