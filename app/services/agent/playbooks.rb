# The diagnostic protocols of the agent (A08): for each consistency check, each invariant it replays and the generic analysis of a variation, a Markdown file in `playbooks/` that says what the symptom is,
# the frequent causes in order, which tools to call, how to read what they give, the steps to correct it in the application (each pointing to a screen) and when to stop and ask an accountant. The file
# says whether an accountant validated its content (`validated: true` in its heading); until then the agent says so and lowers its certainty. The protocols are the application's own text, not data.
module Agent::Playbooks
  DIR = File.expand_path("playbooks", __dir__)
  SECTIONS = { "Symptom" => :symptom, "Frequent causes" => :causes, "Checks" => :checks, "Interpretation" => :interpretation, "Fix" => :fix_steps, "Prevention" => :prevention, "Escalate" => :escalate }.freeze
  SCREEN = /\s*\[\[screen:([\w]+)\]\]/

  Playbook = Data.define(:id, :title, :validated, :symptom, :causes, :checks, :interpretation, :fix_steps, :prevention, :escalate) do
    # Plain hash for a tool result: every step of the fix points to a reference that opens a screen.
    def to_h_for_tool
      { "id" => id, "title" => title, "validated" => validated, "symptom" => symptom, "frequent_causes" => causes, "checks" => checks.map { |check| { "tool" => check[:tool], "why" => check[:why] } },
        "interpretation" => interpretation, "fix_steps" => fix_steps.map { |step| { "step" => step[:text], "ref" => (Agent::Screens.ref(step[:screen]) if step[:screen]) }.compact },
        "prevention" => prevention, "escalate_when" => escalate }
    end
  end

  def self.ids = Dir[File.join(DIR, "*.md")].map { |file| File.basename(file, ".md") }.sort

  def self.all = ids.map { |id| find(id) }

  def self.find(id)
    return unless id.to_s.match?(/\A[A-Za-z0-9_]+\z/)

    file = File.join(DIR, "#{id}.md")
    parse(File.read(file)) if File.exist?(file)
  end

  # The protocol that applies to a finding of the consistency checks: the invariant a C11 anomaly names, else the check itself.
  def self.for_finding(check_id, data = {})
    find(check_id == "C11" && data["invariant"].present? ? data["invariant"] : check_id) || find(check_id)
  end

  def self.parse(source)
    _, heading, body = source.split(/^---\s*$/, 3)
    meta = YAML.safe_load(heading)
    sections = body.split(/^## /).drop(1).to_h { |block| title, *lines = block.lines; [ title.strip, lines.join.strip ] }
    values = SECTIONS.to_h { |title, key| [ key, sections.fetch(title) ] }
    Playbook.new(id: meta.fetch("id"), title: meta.fetch("title"), validated: meta["validated"] == true, symptom: values[:symptom], causes: list(values[:causes]), checks: checks(values[:checks]),
                 interpretation: values[:interpretation], fix_steps: fix_steps(values[:fix_steps]), prevention: values[:prevention].gsub(SCREEN, ""), escalate: values[:escalate])
  end
  private_class_method :parse

  def self.list(text) = text.lines.map { |line| line.strip.sub(/\A(\d+\.|-)\s*/, "") }.reject(&:empty?)
  private_class_method :list

  def self.checks(text)
    list(text).map do |line|
      tool = line[/\A`(\w+)`/, 1]
      { tool: tool, why: line.sub(/\A`\w+`\s*/, "").sub(/\A\([^)]*\):?\s*/, "").strip.presence || line }
    end
  end
  private_class_method :checks

  def self.fix_steps(text)
    list(text).map { |line| { text: line.gsub(SCREEN, "").strip, screen: line[SCREEN, 1] } }
  end
  private_class_method :fix_steps
end
