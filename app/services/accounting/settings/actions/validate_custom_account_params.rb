class Accounting::Settings::Actions::ValidateCustomAccountParams
  extend LightService::Action

  expects :params

  executed do |ctx|
    p = ctx.params

    parent = Accounting::Account.find_by(id: p[:parent_id])
    unless parent
      ctx.fail!("A parent account is required for custom accounts")
      next ctx
    end

    unless p[:code].present? && p[:code].start_with?(parent.code)
      ctx.fail!("Account code must start with the parent account code (#{parent.code})")
      next ctx
    end

    ctx[:parent] = parent
  end
end
