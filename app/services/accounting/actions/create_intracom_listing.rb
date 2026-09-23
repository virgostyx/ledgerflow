class Accounting::Actions::CreateIntracomListing
  extend LightService::Action

  expects :fiscal_year_id, :period_start, :period_end, :listing_lines
  promises :intracom_listing

  executed do |ctx|
    listing = Accounting::IntracomListing.create!(
      fiscal_year_id: ctx.fiscal_year_id,
      period_start:   ctx.period_start,
      period_end:     ctx.period_end
    )

    ctx.listing_lines.each do |(partner_id, code), amount|
      Accounting::IntracomListingLine.create!(
        intracom_listing: listing, partner_id: partner_id, code: code, amount: amount
      )
    end

    ctx.intracom_listing = listing
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!(e.record.errors.full_messages.join(", "))
  end
end
