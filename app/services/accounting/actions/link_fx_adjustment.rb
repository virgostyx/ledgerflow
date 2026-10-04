# The exchange difference that a lettering generated is linked to it (F11), so that undoing the lettering finds it. Written straight to the column:
# a validated entry is immutable, and this changes nothing in it.
class Accounting::Actions::LinkFxAdjustment
  extend LightService::Action

  expects :lettering

  executed do |ctx|
    ctx[:fx_entry]&.update_columns(lettering_id: ctx.lettering.id)
  end
end
