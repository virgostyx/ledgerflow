# The first user of a production install (no sign-up, no seeds there): the owner of the firm, an administrator. Run in a terminal so that the password is typed, not
# written in an argument or in the shell history: bin/kamal app exec --interactive "bin/rails users:create_owner[owner@firm.be,'Full Name']"
require "io/console"

namespace :users do
  desc "Makes the first administrator: users:create_owner[email,full_name]; the password is read from the terminal"
  task :create_owner, %i[email full_name] => :environment do |_, args|
    abort "usage: users:create_owner[email,full_name]" if args[:email].blank? || args[:full_name].blank?
    abort "#{args[:email]} already has an account: nothing changed." if User.exists?(email: args[:email].downcase)

    read = lambda do |prompt|
      $stderr.print prompt
      line = $stdin.tty? ? $stdin.noecho(&:gets) : $stdin.gets
      $stderr.puts if $stdin.tty?
      line.to_s.chomp
    end
    password = read.call("Password (12 characters at least): ")
    abort "The password is too short (12 characters at least)." if password.length < 12
    abort "The two passwords differ." unless password == read.call("Again: ")

    user = User.create!(email: args[:email], full_name: args[:full_name], password: password, password_confirmation: password, role: :admin, active: true)
    puts "Administrator #{user.email} created. Sign in, then create the company."
  end
end
