require 'rails_helper'

# The image runs the external programs the code calls: one missing makes a feature fail only in production. This lists them, and fails when the code calls a new one.
RSpec.describe 'Dockerfile' do
  let(:dockerfile) { Rails.root.join('Dockerfile').read }
  # What the final image installs: the first stage ("base") is the one the final stage starts from.
  let(:runtime_packages) { dockerfile[/FROM docker.io.* AS base(.*?)FROM base AS build/m, 1].scan(/apt-get install(?:[^\n]*\\\n)*[^\n]*/).join(' ').split }

  PROGRAMS = {
    'gs' => 'ghostscript', 'convert' => 'imagemagick', 'identify' => 'imagemagick', 'tesseract' => 'tesseract-ocr',
    'pdftoppm' => 'poppler-utils', 'pdfseparate' => 'poppler-utils', 'pdfunite' => 'poppler-utils',
    'openssl' => nil, # part of the ruby image
    'git' => nil # only the fallback of the revision, which the deployment gives (no .git in the image)
  }.freeze

  def called_programs
    sources = Dir[Rails.root.join('{app,lib}/**/*.{rb,rake}')].map { |path| File.read(path) }
    sources.flat_map do |source|
      source.scan(/ExternalCommand\.run\(\s*"(\w+)"/) + source.scan(/Open3\.\w+\(\s*"(\w+)"/) + source.scan(/\bdef gs\(.*?\[\s*"(\w+)"/) +
        source.scan(/\brun\("(\w+)"/) + source.scan(/(?:=|\|\||\()\s*`(\w+) /)
    end.flatten.uniq
  end

  it 'knows every external program the code calls' do
    expect(called_programs - PROGRAMS.keys).to be_empty, 'a new external program: install its package in the Dockerfile and list it here'
  end

  it 'installs the package of each program in the final image' do
    PROGRAMS.each_value.compact.uniq.each { |package| expect(runtime_packages).to include(package) }
  end

  it 'reads HEIC photos and prints the watermark font and the languages of the OCR' do
    %w[libheif1 libmagickcore-6.q16-6-extra fonts-urw-base35 tesseract-ocr-fra tesseract-ocr-nld tesseract-ocr-eng].each { |package| expect(runtime_packages).to include(package) }
  end

  it 'builds with the Ruby of the project' do
    expect(dockerfile).to match(/^ARG RUBY_VERSION=#{Regexp.escape(Rails.root.join('.ruby-version').read.strip)}$/)
  end

  it 'limits what ImageMagick reads: no PostScript, PDF, vector or network coder, no @file' do
    policy = Rails.root.join('config/imagemagick-policy.xml').read
    %w[PS PS2 PS3 EPS PDF XPS MVG MSL URL HTTP HTTPS FTP].each { |coder| expect(policy).to match(/<policy domain="coder" rights="none" pattern="#{coder}"\s*\/>/) }
    expect(policy).to match(%r{<policy domain="path" rights="none" pattern="@\*"\s*/>})
    expect(dockerfile).to match(%r{COPY config/imagemagick-policy.xml /etc/ImageMagick-6/policy.xml})
  end

  it 'precompiles the assets without the secrets of production' do
    precompile = dockerfile[/^RUN (?:[^\n]*\\\n)*[^\n]*assets:precompile[^\n]*/]
    expect(precompile).to include('SECRET_KEY_BASE_DUMMY=1')
    %w[APP_HOST MAILER_FROM SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD].each { |name| expect(precompile).to include("#{name}=") }
    expect(dockerfile).not_to match(/^ENV[^\n]*SMTP_PASSWORD/)
  end
end
