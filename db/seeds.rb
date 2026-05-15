require_relative 'seeders/pcmn_seeder'
require_relative 'seeders/journals_seeder'

Seeders::PcmnSeeder.call
Seeders::JournalsSeeder.call
