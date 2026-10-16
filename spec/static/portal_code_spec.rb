require 'rails_helper'
require 'ripper'
require 'erb'

# B02a: the portal publishes, it does not expose. Its code reads only portal_* tables and views and never calls a service of the books, of the reports, nor
# the accounting models. A class that refers to anything outside this list fails the suite: adding to the list is a decision to take in review.
RSpec.describe 'Code of the client portal' do
  def allowed_roots = %w[
    Portal PortalUser Rails ApplicationRecord ApplicationMailer ActionController ActionView ActionMailer ActionDispatch ActiveSupport ActiveRecord ActiveModel ActiveStorage
    Rack BCrypt Digest SecureRandom OpenSSL Base64 CGI ERB URI JSON I18n Time Date DateTime Duration Totp WebAuthn RQRCode
    Object Module Class Struct Set Comparable Integer Float String Symbol Array Hash Regexp Range NilClass TrueClass FalseClass Numeric
    StandardError ArgumentError RuntimeError KeyError TypeError NotImplementedError ActionController::Base
    Mime Kernel Process Zlib StringIO File Pathname BigDecimal
  ]

  # Services of the application the portal may call, by their full name: generic file tools that know nothing of the books.
  def allowed_paths = %w[Accounting::WatermarkFile]

  def portal_files
    %w[app/controllers/portal app/models/portal app/services/portal app/jobs/portal app/mailers/portal app/views/portal app/views/layouts/portal app/constraints/portal app/helpers/portal]
      .flat_map { |dir| Dir[Rails.root.join(dir, '**', '*.{rb,erb}')] }
      .push(*Dir[Rails.root.join('app/models/portal_user.rb')], *Dir[Rails.root.join('app/models/portal.rb')]).uniq
  end

  # The scoped name that starts at token i: Accounting::WatermarkFile
  def source_path_at(tokens, i)
    name = tokens[i][2]
    j = i
    while tokens[j + 1] && tokens[j + 1][1] == :on_op && tokens[j + 1][2] == '::' && tokens[j + 2] && tokens[j + 2][1] == :on_const
      name += "::#{tokens[j + 2][2]}"
      j += 2
    end
    name
  end

  def constants_in(path)
    path = path.to_s
    source = File.read(path)
    source = ERB.new(source, trim_mode: '-').src if path.end_with?('.erb')
    tokens = Ripper.lex(source).reject { |(_, type, _)| type == :on_sp }
    roots = []
    defined = []
    tokens.each_with_index do |(_, type, text), i|
      next unless type == :on_const

      previous = tokens[i - 1]
      continues = previous && previous[1] == :on_op && previous[2] == '::' && i > 1 && tokens[i - 2][1] == :on_const
      if !continues && allowed_paths.any? { |path| (name = source_path_at(tokens, i)) == path || name.start_with?("#{path}::") }
        next
      end
      defines = tokens[i + 1] && tokens[i + 1][1] == :on_op && tokens[i + 1][2] == '='
      defined << text if defines
      roots << text unless continues || defines
    end
    (roots - defined).uniq # a constant the file defines itself is its own
  end

  it 'finds the files of the portal' do
    expect(portal_files).to include(a_string_ending_with('app/controllers/portal/base_controller.rb'))
  end

  it 'refers to nothing outside the portal and the framework' do
    offenders = portal_files.flat_map { |path| (constants_in(path) - allowed_roots).map { |c| "#{path.sub(Rails.root.to_s + '/', '')}: #{c}" } }

    expect(offenders).to be_empty, "the portal may not refer to: #{offenders.join(', ')}"
  end

  it 'would notice a service of the books (the check itself)' do
    file = Rails.root.join('tmp/portal_probe.rb')
    File.write(file, "class Portal::Probe\n  def x = Ledger::PostEntry.call\n  def y = ::Accounting::Account.all\nend\n")

    expect(constants_in(file) - allowed_roots).to contain_exactly('Ledger', 'Accounting')
  ensure
    FileUtils.rm_f(file)
  end
end
