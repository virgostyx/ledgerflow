require "open3"
require "tmpdir"

# B03c: a timestamp authority for the specs (RFC 3161), made with the `openssl ts` of the machine: its own CA, a signing certificate with the timestamping usage, and answers that
# are real TimeStampResp. No network. `transport` is what the application calls instead of the HTTP request.
class TestTimestampAuthority
  attr_reader :ca_pem, :queries, :directory

  def initialize
    @queries = []
    @directory = Dir.mktmpdir("tsa")
    build_certificates
    write_config
  end

  def destroy = FileUtils.rm_rf(directory)

  # => a callable (url, query_der) -> response_der
  def transport(unavailable: false)
    lambda do |_url, query|
      queries << query
      raise IOError, "the authority does not answer" if unavailable

      reply(query)
    end
  end

  # The answer of another authority than the one the application trusts (its certificate is not the one configured).
  def reply(query)
    File.binwrite(path("query.tsq"), query)
    _, error, status = Open3.capture3("openssl", "ts", "-reply", "-config", path("tsa.cnf"), "-section", "tsa_config", "-queryfile", path("query.tsq"), "-out", path("response.tsr"))
    raise "the test authority failed: #{error}" unless status.success?

    File.binread(path("response.tsr"))
  end

  private

  def path(name) = File.join(directory, name)

  def build_certificates
    ca_key = OpenSSL::PKey::RSA.new(2048)
    ca = certificate("CN=Test CA", ca_key, nil, ca_key, extensions: [ [ "basicConstraints", "CA:TRUE", true ], [ "keyUsage", "keyCertSign,cRLSign", true ] ])
    tsa_key = OpenSSL::PKey::RSA.new(2048)
    tsa = certificate("CN=Test TSA", tsa_key, ca, ca_key, extensions: [ [ "extendedKeyUsage", "timeStamping", true ], [ "keyUsage", "digitalSignature", true ] ])
    @ca_pem = ca.to_pem
    File.write(path("ca.crt"), ca.to_pem)
    File.write(path("tsa.crt"), tsa.to_pem)
    File.write(path("tsa.key"), tsa_key.to_pem)
    File.write(path("tsa.serial"), "01\n")
  end

  def certificate(subject, key, issuer_cert, issuer_key, extensions:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = SecureRandom.random_number(2**32)
    cert.subject = OpenSSL::X509::Name.parse("/#{subject.tr(',', '/')}")
    cert.issuer = issuer_cert ? issuer_cert.subject : cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 3600
    cert.not_after = Time.now + 86_400
    factory = OpenSSL::X509::ExtensionFactory.new(issuer_cert || cert, cert)
    extensions.each { |name, value, critical| cert.add_extension(factory.create_extension(name, value, critical)) }
    cert.sign(issuer_key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def write_config
    File.write(path("tsa.cnf"), <<~CNF)
      [ tsa ]
      default_tsa = tsa_config
      [ tsa_config ]
      dir = #{directory}
      serial = $dir/tsa.serial
      crypto_device = builtin
      signer_cert = $dir/tsa.crt
      certs = $dir/ca.crt
      signer_key = $dir/tsa.key
      signer_digest = sha256
      default_policy = 1.2.3.4.1
      other_policies = 1.2.3.4.5.6
      digests = sha256
      accuracy = secs:1
      ordering = yes
      tsa_name = yes
      ess_cert_id_chain = no
      ess_cert_id_alg = sha256
    CNF
  end
end

RSpec.shared_context "with a timestamp authority" do
  let!(:authority) { TestTimestampAuthority.new }

  after { authority.destroy }
end
