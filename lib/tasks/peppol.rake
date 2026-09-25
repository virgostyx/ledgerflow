namespace :peppol do
  desc "Simulator: deliver a message left queued (receiver ending with -SLOW): peppol:simulator:deliver[MESSAGE_ID]"
  task "simulator:deliver", [ :message_id ] => :environment do |_, args|
    abort "Development/test only" unless Rails.configuration.x.peppol_simulator_allowed

    result = Peppol::HandleEvent.call(event: Peppol::Event.new(kind: :delivered, message_id: args.fetch(:message_id)))
    abort "No invoice with message #{args[:message_id]}" if result[:ignored]
    puts "Delivered"
  end

  desc "Simulator: book an incoming invoice addressed to an entity: peppol:simulator:receive[ENTITY_ID]"
  task "simulator:receive", [ :entity_id ] => :environment do |_, args|
    abort "Development/test only" unless Rails.configuration.x.peppol_simulator_allowed

    entity = ActsAsTenant.without_tenant { Entity.find(args.fetch(:entity_id)) }
    abort "Entity #{entity.name} is not on the simulator" unless entity.peppol_ap_simulator?

    result = Peppol::AccessPoint.for(entity).simulate_incoming
    abort result.message if result.failure?
    puts "Booked draft invoice #{result[:invoice].external_ref}"
  rescue Peppol::AccessPoint::Error => e
    abort e.message
  end
end
