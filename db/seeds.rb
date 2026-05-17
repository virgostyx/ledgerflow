require_relative 'seeders/pcmn_seeder'
require_relative 'seeders/journals_seeder'
require_relative 'seeders/analytical_axes_seeder'
require_relative 'seeders/users_seeder'

Seeders::PcmnSeeder.call
Seeders::JournalsSeeder.call
Seeders::AnalyticalAxesSeeder.call
Seeders::UsersSeeder.call
