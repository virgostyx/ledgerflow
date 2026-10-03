# Files a VAT declaration (draft -> submitted) and locks its period through the period locks (kind VAT), so nothing can be
# posted with a date inside a filed period afterwards; a correction goes in the next period, or an owner unlocks with a
# reason. One transaction: no lock, no filing.
class Accounting::SubmitVatDeclaration
  def self.call(declaration:, user:)
    ctx = LightService::Context.make(declaration: declaration)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.vat_declarations.errors.invalid_transition")) } unless declaration.draft?

    ApplicationRecord.transaction do
      locked = Accounting::LockPeriod.call(starts_on: declaration.period_start, ends_on: declaration.period_end, kind: :vat, user: user,
                                           reason: "VAT declaration #{declaration.period_start} to #{declaration.period_end} submitted")
      if locked.failure?
        ctx.fail!(locked.message)
        raise ActiveRecord::Rollback
      end
      declaration.submit!
    end
    ctx
  end
end
