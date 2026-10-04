# Daily (F11): loads the exchange rates of every entity that turned `f11` on: the ECB's daily reference rates, and the InforEuro monthly rates of this
# month and of the last one (a month is published at the start of the month or the one before, and a month not published yet is no error). This is the
# only thing in the application that goes to the network for rates; entering an invoice or an entry never does. A source that fails is logged and the
# others go on; the next run tries again, and the screen shows what is still missing.
class Rates::ImportJob < ApplicationJob
  queue_as :default

  def perform
    Entity.find_each do |entity|
      next unless entity.feature?(:f11)

      ActsAsTenant.with_tenant(entity) { import }
    end
  end

  private

  def import
    load_from("ECB") { Rates::Ecb.daily }
    today = Date.current
    [ today, today.prev_month ].each do |day|
      load_from("InforEuro #{day.year}/#{day.month}") { Rates::InforEuro.month(day.year, day.month) }
    end
  end

  def load_from(label)
    Rates::Import.call(quotes: yield)
  rescue Rates::NotPublished
    nil
  rescue Rates::Error => e
    Rails.logger.error("[rates] #{label}: #{e.message}")
  end
end
