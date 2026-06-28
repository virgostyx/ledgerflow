module Seeders
  class UsersSeeder
    USERS = [
      {
        full_name: "Alice Admin",
        email: "admin@ledgerflow.test",
        password: "password123!",
        role: :admin,
        active: true
      },
      {
        full_name: "Charles Comptable",
        email: "comptable@ledgerflow.test",
        password: "password123!",
        role: :accountant,
        active: true
      },
      {
        full_name: "Marie Manager",
        email: "manager@ledgerflow.test",
        password: "password123!",
        role: :manager,
        active: true
      },
      {
        full_name: "André Auditeur",
        email: "auditeur@ledgerflow.test",
        password: "password123!",
        role: :auditor,
        active: true
      },
      {
        full_name: "Bruno Budget",
        email: "budget@ledgerflow.test",
        password: "password123!",
        role: :budget_user,
        active: true
      }
    ].freeze

    def self.call
      new.call
    end

    def call
      counts = { created: 0, skipped: 0 }

      USERS.each do |attrs|
        user = User.find_or_initialize_by(email: attrs[:email])
        if user.new_record?
          user.assign_attributes(attrs)
          user.save!
          counts[:created] += 1
        else
          counts[:skipped] += 1
        end
      end

      puts "[Users] #{counts[:created]} utilisateurs créés, #{counts[:skipped]} déjà présents."
      puts ""
      puts "  Comptes de test :"
      USERS.each do |u|
        puts "    #{u[:role].to_s.ljust(12)} #{u[:email]}  /  #{u[:password]}"
      end
    end
  end
end
