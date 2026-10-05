namespace :closing do
  desc "Move the entities that carry their result to 130000 to 140100 (profit) and 140200 (loss), or 120100 and 120200 for an association, where their chart has both accounts; the others are listed, untouched"
  task use_retained_earnings_accounts: :environment do
    Entity.find_each do |entity|
      next unless entity.closing_carry_account_code == "130000"

      codes = Seeders::PcmnSeeder::ASBL_LEGAL_FORMS.include?(entity.legal_form) ? Seeders::PcmnSeeder::ASBL_CARRY.values : %w[140100 140200]
      has = ActsAsTenant.with_tenant(entity) { codes.all? { |code| Accounting::Account.exists?(code: code) } }
      if has
        entity.update!(closing_carry_account_code: codes.first, closing_loss_account_code: codes.last)
        puts "#{entity.name}: now #{codes.join(' / ')} (what it already carried on 130000 stays there)"
      else
        puts "#{entity.name}: left on 130000: its chart has no #{codes.join(' and ')} (create them, then run this again)"
      end
    end
  end
end
