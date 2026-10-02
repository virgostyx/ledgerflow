require "rails_helper"

RSpec.describe Accounting::ExternalCommand do
  it "returns what the program wrote" do
    expect(described_class.run("echo", "hello")).to eq("hello\n")
  end

  it "feeds the program through its standard input" do
    expect(described_class.run("cat", input: "from stdin")).to eq("from stdin")
  end

  it "feeds binary data (a file) through unchanged" do
    bytes = (0..255).map(&:chr).join.b * 10

    expect(described_class.run("cat", input: bytes).b).to eq(bytes)
  end

  it "feeds a large input without blocking" do
    big = "x" * 2_000_000

    expect(described_class.run("cat", input: big).bytesize).to eq(big.bytesize)
  end

  it "never gives a shell what it is asked to run: metacharacters are plain text" do
    expect(described_class.run("echo", "a; rm -rf / && $(whoami) `id` | cat")).to eq("a; rm -rf / && $(whoami) `id` | cat\n")
  end

  it "raises when the program fails, with the first line it complained about" do
    expect { described_class.run("sh", "-c", "echo oops >&2; exit 3") }.to raise_error(described_class::Failed, /oops/)
  end

  it "kills a program that takes too long" do
    started = Time.current

    expect { described_class.run("sleep", "30", timeout: 1) }.to raise_error(described_class::Failed, /took too long/)
    expect(Time.current - started).to be < 5
  end

  it "says when the program is not installed" do
    expect { described_class.run("no-such-program-here") }.to raise_error(described_class::Failed, /not installed/)
  end

  it "lets a caller read the exit code of a program that answers by it (a scanner)" do
    output, code, = described_class.run_with_status("sh", "-c", "echo found; exit 1")

    expect(code).to eq(1)
    expect(output).to eq("found\n")
  end

  it "gives the exit code 0 and the output of a program that succeeds" do
    expect(described_class.run_with_status("echo", "ok")).to eq([ "ok\n", 0, "" ])
  end
end
