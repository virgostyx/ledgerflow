# Collects the lines linked to the allocated ones. Fully settled: letter them (which marks invoices paid).
# Otherwise: reflect the partial payment on the invoices.
class Accounting::Actions::CloseSettledGroup
  extend LightService::Action

  expects :lines
  promises :lettering

  executed do |ctx|
    ctx.lettering = nil
    group = Accounting::LineAllocation.group_lines(ctx.lines)

    if group.all? { |l| l.open_amount.zero? }
      lettered = Accounting::LetterLines.call(lines: group)
      next ctx.fail_with_rollback!(lettered.message) if lettered.failure?

      ctx.lettering = lettered.lettering
    else
      Accounting::SyncInvoiceStatus.call(group)
    end
  end
end
