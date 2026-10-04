# An event from an Access Point, in the same shape whichever provider it comes from.
# kind: :delivered, :failed (both about a sent document, found by message_id) or :received (a document for an entity,
# found by the receiver participant id).
# remote_id: the Access Point's identifier of a received document announced without its XML (it is fetched afterwards).
Peppol::Event = Struct.new(:kind, :message_id, :receiver, :xml, :error, :sender, :raw, :remote_id, keyword_init: true)
