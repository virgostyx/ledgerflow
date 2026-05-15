class Users::SessionsController < Devise::SessionsController
  layout "devise"

  protected

  def after_sign_in_path_for(resource)
    accounting_root_path
  end

  def after_sign_out_path_for(resource_or_scope)
    root_path
  end
end
