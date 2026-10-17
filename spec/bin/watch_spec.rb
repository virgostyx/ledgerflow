require 'rails_helper'
require 'open3'
require 'tmpdir'

# bin/watch runs on the server (cron, every hour): disk, backups, recurring jobs. It mails only when something is wrong. Fake df, docker and curl: nothing real is touched.
RSpec.describe 'bin/watch' do
  let(:script) { Rails.root.join('bin/watch').to_s }
  let(:home) { Dir.mktmpdir('watch') }
  let(:backups) { File.join(home, 'backups').tap { |dir| FileUtils.mkdir_p(dir) } }
  let(:curl_log) { File.join(home, 'curl.log') }
  let(:env_file) { File.join(home, '.ledgerflow-watch.env') }

  def fake(name, body)
    FileUtils.mkdir_p(File.join(home, 'fakebin'))
    File.write(File.join(home, 'fakebin', name), "#!/usr/bin/env bash\n#{body}\n")
    FileUtils.chmod(0o755, File.join(home, 'fakebin', name))
  end

  before do
    fake('df', 'printf "Use%%\n %s%%\n" "${FAKE_DISK:-40}"')
    fake('docker', 'if [ "${FAKE_DOCKER:-ok}" = fail ]; then exit 1; fi; echo "${FAKE_RECURRING:-12}"')
    fake('curl', %(echo "$@" >> "#{curl_log}"; cat > "#{curl_log}.stdin";))
    File.write(env_file, "ALERT_SMTP_URL=smtps://smtp.example.test:465\nALERT_USER=alerts@example.test\nALERT_PASSWORD=very-secret-value\nALERT_TO=owner@example.test\n")
    FileUtils.touch(File.join(backups, 'db-20261017-023000.dump'))
    FileUtils.touch(File.join(home, '.offsite_last_success'))
  end

  after { FileUtils.rm_rf(home) }

  def run_script(env = {})
    Open3.capture3({ 'PATH' => "#{home}/fakebin:#{ENV['PATH']}", 'HOME' => home, 'BACKUP_DIR' => backups }.merge(env), script)
  end

  def old(path) = File.utime(Time.now - (3 * 86_400), Time.now - (3 * 86_400), path)
  def mails = File.exist?(curl_log) ? File.readlines(curl_log).size : 0

  it 'says nothing and mails nothing when all is well' do
    out, _err, status = run_script
    expect(status).to be_success
    expect(out.strip).to eq('ok')
    expect(mails).to eq(0)
  end

  it 'reports a disk that fills up, and mails it' do
    out, _err, status = run_script('FAKE_DISK' => '91')
    expect(status).not_to be_success
    expect(out).to match(/disk.*91/i)
    expect(mails).to eq(1)
  end

  it 'reports a local backup older than a day' do
    old(File.join(backups, 'db-20261017-023000.dump'))
    out, _err, status = run_script
    expect(status).not_to be_success
    expect(out).to match(/local backup/i)
  end

  it 'reports a missing local backup' do
    FileUtils.rm(Dir[File.join(backups, 'db-*')])
    expect(run_script[0]).to match(/local backup/i)
  end

  it 'reports an offsite copy that has not succeeded for a day, or never did' do
    old(File.join(home, '.offsite_last_success'))
    expect(run_script[0]).to match(/offsite/i)
    FileUtils.rm(File.join(home, '.offsite_last_success'))
    expect(run_script('FAKE_DISK' => '40')[0]).to match(/offsite/i)
  end

  it 'reports recurring jobs that stopped, or a database that does not answer' do
    expect(run_script('FAKE_RECURRING' => '0')[0]).to match(/recurring/i)
    expect(run_script('FAKE_DOCKER' => 'fail')[0]).to match(/recurring/i)
  end

  it 'never puts the SMTP password on a command line' do
    run_script('FAKE_DISK' => '95')
    expect(File.read(curl_log)).not_to include('very-secret-value')
    expect(File.read("#{curl_log}.stdin")).to include('very-secret-value')
  end

  it 'mails the owner once per 12 hours, whatever the number of problems' do
    2.times { run_script('FAKE_DISK' => '95') }
    expect(mails).to eq(1)
    old(File.join(home, '.watch_last_alert'))
    run_script('FAKE_DISK' => '95')
    expect(mails).to eq(2)
  end

  it 'still reports on its output when no mail is configured' do
    FileUtils.rm(env_file)
    out, _err, status = run_script('FAKE_DISK' => '95')
    expect(status).not_to be_success
    expect(out).to match(/disk/i)
    expect(out).to match(/no mail/i)
    expect(mails).to eq(0)
  end
end
