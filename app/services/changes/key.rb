# B03b: the identity of a change that is not an entry, stable from one report to the next, so that a review stays on it ("entry:<id>" for an entry).
module Changes::Key
  def self.for(event) = [ event.category, event.subject_type, event.subject_id, event.action, event.at.utc.iso8601(6) ].join(":")
end
