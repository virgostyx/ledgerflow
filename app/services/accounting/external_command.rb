# Runs an external program (tesseract, pdftoppm, pdfseparate, gs, clamscan...) the safe way: an argument list, never a
# shell, so that nothing a file or a name contains can become a command; a time limit, after which the process is
# killed; optional data on its standard input.
module Accounting::ExternalCommand
  class Failed < StandardError; end

  # => the standard output; raises Failed if the program fails or takes more than `timeout` seconds
  def self.run(*command, timeout: 90, input: nil)
    output, code, error = run_with_status(*command, timeout: timeout, input: input)
    raise Failed, "#{command.first} failed: #{error.to_s.lines.first&.strip}" unless code.zero?

    output
  end

  # => [standard output, exit code, standard error], for a program that answers by its exit code (a virus scanner:
  # 0 clean, 1 infected, 2 error). Still raises Failed on a timeout or a program that is not installed.
  def self.run_with_status(*command, timeout: 90, input: nil)
    Open3.popen3(*command) do |stdin, stdout, stderr, waiter|
      writer = Thread.new do
        stdin.binmode
        stdin.write(input.b) if input # a file is bytes, not text
      rescue Errno::EPIPE
        nil # the program did not want all of it
      ensure
        stdin.close
      end
      out = Thread.new { stdout.read }
      err = Thread.new { stderr.read }
      unless waiter.join(timeout)
        Process.kill("KILL", waiter.pid)
        raise Failed, "#{command.first} took too long"
      end
      writer.join
      [ out.value, waiter.value.exitstatus, err.value ]
    end
  rescue Errno::ENOENT
    raise Failed, "#{command.first} is not installed"
  end
end
