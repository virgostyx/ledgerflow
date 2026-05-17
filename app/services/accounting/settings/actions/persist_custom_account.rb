class Accounting::Settings::Actions::PersistCustomAccount
  extend LightService::Action

  expects :params, :parent

  executed do |ctx|
    p      = ctx.params
    parent = ctx.parent

    account = Accounting::Account.new(
      parent:         parent,
      code:           p[:code],
      label_fr:       p[:label_fr],
      label_nl:       p[:label_nl],
      account_class:  p[:account_class] || parent.account_class,
      account_type:   p[:account_type]  || parent.account_type,
      normal_balance: p[:normal_balance] || parent.normal_balance,
      custom:         true,
      is_leaf:        true,
      active:         true
    )

    unless account.save
      ctx.fail!(account.errors.full_messages.join(", "))
      next ctx
    end

    ctx[:account] = account
  end
end
