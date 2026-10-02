# The point of entry for an antivirus (F03). Off unless a scanner is configured (config.x.document_virus_scan, from the
# environment: DOCUMENT_VIRUS_SCAN_COMMAND, e.g. "clamdscan --no-summary --stream -", which reads the file on its standard
# input). The scanner answers by its exit code: 0 clean, 1 infected, anything else (or not installed, or too slow) means
# it could not check: the file is then refused, never let in unchecked, unless DOCUMENT_VIRUS_SCAN_FAIL_OPEN says so.
# A file the scanner calls infected is never let through, whatever the setting.
# => :clean, :infected or :unavailable
class Accounting::VirusScan
  TIMEOUT = 60

  def self.call(bytes)
    setting = Rails.configuration.x.document_virus_scan
    return :clean unless setting

    _output, code, = Accounting::ExternalCommand.run_with_status(*setting.fetch(:command), input: bytes, timeout: TIMEOUT)
    case code
    when 0 then :clean
    when 1 then :infected
    else unavailable(setting)
    end
  rescue Accounting::ExternalCommand::Failed => e
    Rails.logger.error("[documents] virus scan failed: #{e.message}")
    unavailable(setting)
  end

  def self.unavailable(setting) = setting[:fail_open] ? :clean : :unavailable
  private_class_method :unavailable
end
