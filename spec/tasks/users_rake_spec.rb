require "rails_helper"
require "rake"

# Production has no sign-up and no seeds: the first user, the owner of the firm, is made from the command line. The password is read from the terminal, never from an argument.
RSpec.describe "users:create_owner" do
  before(:all) do
    Rake.application.rake_require("tasks/users", [ Rails.root.join("lib").to_s ], [])
    Rake::Task.define_task(:environment)
  end

  PASSWORD = "a long passphrase 42".freeze

  def run_task(*args, input: "#{PASSWORD}\n#{PASSWORD}\n")
    task = Rake::Task["users:create_owner"]
    task.reenable
    out = StringIO.new
    previous = [ $stdin, $stdout ]
    $stdin = StringIO.new(input)
    $stdout = out
    task.invoke(*args)
    out.string
  ensure
    $stdin, $stdout = previous
  end

  it "makes an active administrator who can sign in with the password" do
    run_task("owner@example.test", "The Owner")
    user = User.find_by!(email: "owner@example.test")
    expect(user).to be_admin
    expect(user.active).to be(true)
    expect(user.full_name).to eq("The Owner")
    expect(user.valid_password?(PASSWORD)).to be(true)
  end

  it "never prints the password" do
    expect(run_task("owner@example.test", "The Owner")).not_to include(PASSWORD)
  end

  it "refuses a short password" do
    expect { run_task("owner@example.test", "The Owner", input: "short\nshort\n") }.to raise_error(SystemExit)
    expect(User.where(email: "owner@example.test")).to be_empty
  end

  it "refuses a confirmation that differs" do
    expect { run_task("owner@example.test", "The Owner", input: "#{PASSWORD}\nsomething else entirely\n") }.to raise_error(SystemExit)
    expect(User.where(email: "owner@example.test")).to be_empty
  end

  it "does not touch an account that exists" do
    existing = create(:user, email: "owner@example.test", password: "Password123!")
    expect { run_task("owner@example.test", "The Owner") }.to raise_error(SystemExit)
    expect(existing.reload.valid_password?("Password123!")).to be(true)
  end

  it "asks for its arguments" do
    expect { run_task }.to raise_error(SystemExit)
  end
end
