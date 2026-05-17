Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data, "https://fonts.gstatic.com"
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https
    # 'unsafe-inline' needed for the dynamic inline style in journal_entry_form_component
    policy.style_src   :self, :https, "'unsafe-inline'", "https://fonts.googleapis.com"
    # ws/wss required for Turbo Streams via Action Cable (Solid Cable)
    policy.connect_src :self, "ws:", "wss:"
  end

  # Nonce-based protection for inline ImportMap script tags
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
