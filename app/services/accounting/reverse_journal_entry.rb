# F07: cancels a posted entry with a counter-entry (debit and credit swapped) in the same journal. The original is never modified, it is
# flagged reversed when the reversal is posted (Actions::MarkReversedOriginal), which is also what a scheduled draft reversal does when
# a person posts it. Entries born from an invoice or payment batch are undone from their source (from_source: true).
#
# Date: the one asked for (`date:`, it must be in an open period), else the date of the entry (or `from:`, a scheduled reversal's) when its period is open, else the first day of the
# first open period after it, with a warning; a move out of a filed VAT period marks the reversal as a VAT regularisation.
# Lettered lines: refused unless confirm_unletter, then unlettered first with the same reason (a locked period asks the right of `user`).
# draft: true creates the reversal as a draft (scheduled reversals), never posted here.
# => ctx[:reversal], ctx[:warnings]
class Accounting::ReverseJournalEntry
  MAX_MOVES = 60

  Placement = Struct.new(:date, :fiscal_year, :warnings, :vat_regularisation, keyword_init: true)

  def self.call(entry:, from_source: false, reason: nil, date: nil, from: nil, confirm_unletter: false, user: nil, draft: false)
    ctx = LightService::Context.make(entry: entry, reversal: nil, warnings: [])
    refusal = refusal_for(entry, from_source, reason)
    return ctx.tap { |c| c.fail!(refusal) } if refusal

    placement = place(entry, date, from)
    return ctx.tap { |c| c.fail!(placement) } if placement.is_a?(String)

    ApplicationRecord.transaction do
      Accounting::PeriodLock.serialize_for_entity!
      if lettered?(entry)
        next ctx.fail!(I18n.t("accounting.errors.reverse_lettered")) unless confirm_unletter

        problem = unletter(entry, reason, user)
        next ctx.fail!(problem) if problem
      end

      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      reversal = build_reversal(entry, placement, reason)
      reversal.save!
      unless draft
        posted = Accounting::PostJournalEntry.call(entry: reversal)
        if posted.failure?
          ctx.fail!(posted.message)
          raise ActiveRecord::Rollback
        end
      end
      ctx[:reversal] = reversal
      ctx[:warnings] = placement.warnings
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  # What a reversal of this entry would be, for the preview: date, fiscal year, warnings, and whether lines are lettered.
  def self.preview(entry, date: nil)
    placement = place(entry, date)
    { placement: (placement unless placement.is_a?(String)), problem: (placement if placement.is_a?(String)), lettered: lettered?(entry) }
  end

  # A correction of a validated entry needs a reason (R18); reversals born from a source document carry theirs.
  def self.refusal_for(entry, from_source, reason)
    return I18n.t("accounting.errors.reverse_not_posted")  unless entry.posted?
    # (the appropriation of the result is a person's decision of the meeting: it is reversed like any entry, with a reason)
    return I18n.t("accounting.errors.reverse_has_source")  if entry.source_type.present? && !from_source && entry.source_type != Accounting::JournalEntry::APPROPRIATION_SOURCE
    return I18n.t("accounting.errors.reverse_reason_required") if reason.blank? && !from_source
    I18n.t("accounting.errors.reverse_already") if Accounting::JournalEntry.where(reversal_of_id: entry.id).where.not(status: :reversed).exists?
  end

  def self.lettered?(entry)
    entry.lines.where.not(lettering_id: nil).exists? || Accounting::LineAllocation.touching(entry.lines.select(:id)).exists?
  end

  def self.unletter(entry, reason, user)
    entry.lines.where.not(lettering_id: nil).distinct.pluck(:lettering_id).each do |id|
      result = Accounting::UnletterLines.call(lettering: Accounting::Lettering.find(id), reason: reason.presence || I18n.t("accounting.errors.reverse_unletter_reason"), user: user)
      return result.message if result.failure?
    end
    Accounting::LineAllocation.touching(entry.lines.select(:id)).includes(:debit_line, :credit_line).to_a.each do |allocation|
      result = Accounting::RemoveAllocation.call(allocation: allocation)
      return result.message if result.failure?
    end
    nil
  end

  # => a Placement, or a String (why there is none)
  def self.place(entry, requested, from = nil)
    warnings = []
    vat = false
    candidate = requested || from || entry.entry_date
    MAX_MOVES.times do
      year = Accounting::FiscalYear.where("start_date <= :d AND end_date >= :d", d: candidate).first
      if year.nil? || year.closed? # a year waiting to be opened (pre_closing, F10) takes entries as an open one does
        return I18n.t("accounting.errors.reverse_date_closed") if requested

        following = Accounting::FiscalYear.open.where("start_date > ?", candidate).order(:start_date).first
        return I18n.t("accounting.errors.reverse_no_open_year") unless following

        warnings << I18n.t("accounting.errors.reverse_moved_closed_year", date: I18n.l(following.start_date))
        candidate = following.start_date
        next
      end

      lock = Accounting::PeriodLock.covering(candidate).order(ends_on: :desc).first unless Accounting::ControlledWindow.override_on? # an owner's window lifts the locks (F01)
      return Placement.new(date: candidate, fiscal_year: year, warnings: warnings, vat_regularisation: vat) unless lock
      return I18n.t("accounting.errors.reverse_date_locked") if requested

      vat ||= lock.vat?
      warnings << I18n.t(vat && lock.vat? ? "accounting.errors.reverse_moved_vat" : "accounting.errors.reverse_moved_locked", date: I18n.l(lock.ends_on + 1))
      candidate = lock.ends_on + 1
    end
    I18n.t("accounting.errors.reverse_no_open_year")
  end

  def self.build_reversal(entry, placement, reason)
    Accounting::JournalEntry.new(
      journal: entry.journal, fiscal_year: placement.fiscal_year, entry_date: placement.date,
      description: I18n.t("accounting.journal_entries.reversal_description", reference: entry.reference),
      reversal_of_id: entry.id, reversal_reason: reason.presence, vat_regularisation: placement.vat_regularisation
    ).tap do |reversal|
      entry.lines.each do |l|
        foreign = l.currency == "EUR" || l.amount_currency.nil? ? {} : { currency: l.currency, exchange_rate: l.exchange_rate, amount_currency: -l.amount_currency } # F11
        reversal.lines.build(account_id: l.account_id, partner_id: l.partner_id, label: l.label,
                             debit: l.credit, credit: l.debit, sort_order: l.sort_order, **foreign)
      end
    end
  end
  private_class_method :refusal_for, :unletter, :build_reversal
end
