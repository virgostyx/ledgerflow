require_relative 'seeders/pcmn_seeder'
require_relative 'seeders/journals_seeder'
require_relative 'seeders/users_seeder'

Seeders::PcmnSeeder.call
Seeders::JournalsSeeder.call
Seeders::UsersSeeder.call
