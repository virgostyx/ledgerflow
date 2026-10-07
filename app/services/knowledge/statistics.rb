# What the owners of the base want to know (A06): which passages the agent cites most, which documents it never cited, which end their validity soon.
class Knowledge::Statistics
  SOON = 60

  def initialize(entity)
    @entity = entity
  end

  # ponytail: tallied in Ruby over the citations of the entity's answers (counts of references, no amounts); a SQL group over jsonb_array_elements if answers number in the millions.
  def cited = @cited ||= Agent::Message.where.not(citations: []).pluck(:citations).flatten.filter_map { |citation| citation["ref"] if citation["ref"].to_s.start_with?("kb:") }.tally

  def documents = Knowledge::Document.visible_to(@entity).where.not(status: "retired")

  def most_cited(limit = 5) = cited.max_by(limit) { |_, count| count }

  def never_cited = documents.reviewed.reject { |document| cited.keys.any? { |ref| ref.start_with?("kb:doc-#{document.id}:") } }

  def ending_soon = documents.ending_within(SOON).order(:valid_to)
end
