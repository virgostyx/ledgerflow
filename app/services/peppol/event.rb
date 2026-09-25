# An event from an Access Point, in the same shape whichever provider it comes from.
# kind: :delivered, :failed (both about a sent document, found by message_id) or :received (a document for an entity,
# found by the receiver participant id).
Peppol::Event = Struct.new(:kind, :message_id, :receiver, :xml, :error, keyword_init: true)
