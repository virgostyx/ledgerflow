require 'rails_helper'
require 'open3'
require 'tmpdir'

# bin/backup-offsite copies the local backups to the encrypted OVH bucket (rclone crypt). A fake rclone records its calls: nothing leaves the machine.
RSpec.describe 'bin/backup-offsite' do
  let(:script) { Rails.root.join('bin/backup-offsite').to_s }
  let(:home) { Dir.mktmpdir('offsite') }
  let(:backups) { File.join(home, 'backups').tap { |dir| FileUtils.mkdir_p(dir) } }
  let(:log) { File.join(home, 'rclone.log') }

  before do
    FileUtils.mkdir_p(File.join(home, 'fakebin'))
    File.write(File.join(home, 'fakebin/rclone'), <<~SH)
      #!/usr/bin/env bash
      echo "$@" >> "#{log}"
      case " $FAIL_ON " in *" $1 "*) echo "rclone: forced failure" >&2; exit 1;; esac
      if [ -n "${FAIL_MATCH:-}" ]; then case "$*" in *"$FAIL_MATCH"*) echo "rclone: forced failure" >&2; exit 1;; esac; fi
    SH
    FileUtils.chmod(0o755, File.join(home, 'fakebin/rclone'))
  end

  after { FileUtils.rm_rf(home) }

  def run_script(env = {})
    Open3.capture3({ 'PATH' => "#{home}/fakebin:#{ENV['PATH']}", 'HOME' => home, 'BACKUP_DIR' => backups, 'OFFSITE_REMOTE' => 'bucket:', 'OFFSITE_TODAY' => '2026-10-17' }.merge(env), script)
  end

  def calls = File.exist?(log) ? File.readlines(log, chomp: true) : []
  def heartbeat = File.join(home, '.offsite_last_success')

  it 'copies the dumps and the storage archives, without ever overwriting an object' do
    _out, _err, status = run_script
    expect(status).to be_success
    copy = calls.find { |call| call.start_with?('copy') }
    expect(copy).to include(backups, 'bucket:daily', '--immutable', '--include db-*.dump', '--include storage-*.tgz')
  end

  it 'checks what it copied, then writes the heartbeat the watch reads' do
    run_script
    expect(calls.index { |call| call.start_with?('check') }).to be > calls.index { |call| call.start_with?('copy') }
    expect(File.exist?(heartbeat)).to be(true)
  end

  it 'stops at a failed copy: no check, no prune, no heartbeat, a failure status' do
    _out, err, status = run_script('FAIL_ON' => 'copy')
    expect(status).not_to be_success
    expect(err).to include('forced failure')
    expect(calls.map { |call| call.split.first }).to eq(%w[copy])
    expect(File.exist?(heartbeat)).to be(false)
  end

  it 'does not trust a copy that does not check out' do
    _out, _err, status = run_script('FAIL_ON' => 'check')
    expect(status).not_to be_success
    expect(calls.map { |call| call.split.first }).not_to include('delete')
    expect(File.exist?(heartbeat)).to be(false)
  end

  it 'removes the daily copies older than 30 days only after a good check' do
    run_script
    expect(calls.map { |call| call.split.first }).to eq(%w[copy check delete])
    expect(calls.last).to include('bucket:daily', '--min-age 30d')
  end

  it 'survives a refused deletion (object lock still holds the file): a warning, the heartbeat stays' do
    out, err, status = run_script('FAIL_ON' => 'delete')
    expect(status).to be_success
    expect(out + err).to include('warning')
    expect(File.exist?(heartbeat)).to be(true)
  end

  it 'keeps a monthly copy on the first day of the month, never pruned' do
    run_script('OFFSITE_TODAY' => '2026-11-01')
    expect(calls.grep(/bucket:monthly/).size).to eq(1)
    expect(calls.grep(/delete.*monthly/)).to be_empty
    run_script('OFFSITE_TODAY' => '2026-11-02')
    expect(calls.grep(/bucket:monthly/).size).to eq(1)
  end

  # The documents live in the R2 bucket, not in the storage volume: DOCUMENTS_REMOTE (an rclone remote on R2) is copied to the encrypted bucket too.
  describe 'with DOCUMENTS_REMOTE set' do
    let(:docs) { { 'DOCUMENTS_REMOTE' => 'r2:documents-bucket' } }

    it 'copies the R2 bucket to documents/, never overwriting an object, then checks it' do
      _out, _err, status = run_script(docs)
      expect(status).to be_success
      copy = calls.find { |call| call.start_with?('copy r2:documents-bucket') }
      expect(copy).to include('bucket:documents', '--immutable')
      expect(calls).to include(a_string_starting_with('check r2:documents-bucket bucket:documents --one-way'))
    end

    it 'never prunes the documents: a file deleted from R2 stays in the copy' do
      run_script(docs)
      expect(calls.grep(/delete.*documents/)).to be_empty
    end

    it 'writes no heartbeat when the documents copy fails' do
      _out, err, status = run_script(docs.merge('FAIL_MATCH' => 'r2:documents-bucket'))
      expect(status).not_to be_success
      expect(err).to include('forced failure')
      expect(File.exist?(heartbeat)).to be(false)
    end
  end

  it 'does not touch the documents when DOCUMENTS_REMOTE is not set' do
    run_script
    expect(calls.grep(/documents/)).to be_empty
  end

  it 'refuses to run with nothing to copy' do
    FileUtils.rm_rf(backups)
    _out, err, status = run_script
    expect(status).not_to be_success
    expect(err).to include('BACKUP_DIR')
    expect(calls).to be_empty
  end
end
