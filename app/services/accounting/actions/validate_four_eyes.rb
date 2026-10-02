# F01: when the entity requires it, the author of an entry cannot validate it.
class Accounting::Actions::ValidateFourEyes
  extend LightService::Action

  expects :entry

  executed do |ctx|
    ctx.fail_with_rollback!(I18n.t("accounting.errors.four_eyes")) if ctx.entry.four_eyes_blocks?(Current.user)
  end
end
