# Builds the summary of one person in one entity (A10a), with that person's rights: the sources one may see, only what changed since the last summary plus what is urgent, the ten first by priority, and nothing
# at all when there is nothing to say. No model: the text is a template filled with counts. => the digest, or nil. `event`: build only the sources of an event (see Agent::Digest::Events).
class Agent::Digest::Build
  def self.call(user:, entity:, today: Date.current, event: nil, sections: nil) = new(user, entity, today, event, sections).call

  def initialize(user, entity, today, event, sections)
    @user = user
    @entity = entity
    @today = today
    @event = event
    @sections = sections
  end

  def call
    ActsAsTenant.with_tenant(@entity) do
      context = Agent::Context.build(user: @user, entity: @entity, locale: :en, today: @today)
      return if Agent::Access.check(context)

      previous = Agent::Digest.where(user: @user, kind: "scheduled").recent.first&.snapshot || {}
      items = Agent::Digest::Sources.call(context: context, previous: previous, today: @today)
      items = items.select { |item| allowed?(item) }
      shown = items.select { |item| item.urgent || item.changed }.sort_by { |item| -item.priority }.first(Agent::Digest::MAX_ITEMS)
      shown = shown.select { |item| @event.nil? || Agent::Digest::Events::SOURCES.fetch(@event).call(item) } if @event
      return if shown.empty?

      save(shown, items)
    end
  end

  private

  def allowed?(item) = @sections.blank? || @sections.include?(item.section)

  def save(shown, all)
    sections = shown.group_by(&:section).map do |section, rows|
      { "key" => section, "title" => Agent::Digest::Sources::SECTIONS.fetch(section), "items" => rows.map { |item| item_hash(item) } }
    end
    # What the next summary compares with: the state of every source as it is now. An event does not move it, so that the summary of the morning still says what it would have said.
    snapshot = @event ? (Agent::Digest.where(user: @user, kind: "scheduled").recent.first&.snapshot || {}) : all.to_h { |item| [ item.key, item.state ] }
    Agent::Digest.create!(user: @user, kind: @event ? "event" : "scheduled", event_type: @event, local_date: @today, item_count: shown.size, payload: { "sections" => sections, "snapshot" => snapshot }.to_json)
  end

  def item_hash(item)
    { "key" => item.key, "text" => item.text, "detail" => item.detail, "ref" => item.ref, "ask" => item.ask || item.section, "urgent" => item.urgent, "count" => item.count }
  end
end
