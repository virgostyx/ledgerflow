require "rails_helper"

# A03: nothing of an entity may sit in a place that another one reads: no cache shared between entities or people, no memory of the process.
RSpec.describe "The agent keeps no state shared between entities" do
  FILES = Dir[Rails.root.join("app/{services,jobs,controllers,models}/agent/**/*.rb")].sort.freeze

  it "has files to check" do
    expect(FILES.size).to be > 40
  end

  it "does not use the application cache, which is shared by every entity" do
    users = FILES.select { |file| File.read(file).lines.reject { |line| line.strip.start_with?("#") }.join.match?(/Rails\.cache|\bcache\.fetch|Rails\.application\.config\.cache_store/) }

    expect(users.map { |file| File.basename(file) }).to be_empty
  end

  it "keeps no class-level or global variable that could carry one entity's data to another" do
    offenders = FILES.select do |file|
      code = File.read(file).lines.reject { |line| line.strip.start_with?("#") }.join
      code.match?(/\$\w+\s*=|@@\w+\s*=|\bThread\.current\[/) || code.match?(/^\s*(class_attribute|cattr_accessor|mattr_accessor)\b/)
    end

    expect(offenders.map { |file| File.basename(file) }).to be_empty
  end

  it "builds the context of a question afresh, and never lets it change" do
    context = Agent::Context.build(user: User.new, entity: Entity.new, locale: :en)

    expect(context).to be_frozen
  end
end
