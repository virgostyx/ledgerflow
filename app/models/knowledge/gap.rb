# A question the base could not answer, or an answer a person found not useful (A06): what to add to the base, by frequency. The question is encrypted.
class Knowledge::Gap < ApplicationRecord
  self.table_name = "knowledge_gaps"

  KINDS = %w[no_passage not_useful].freeze

  acts_as_tenant :entity

  belongs_to :user, optional: true
  belongs_to :message, class_name: "Agent::Message", optional: true

  encrypts :question

  validates :kind, inclusion: { in: KINDS }

  before_validation { self.question_key = self.class.key_for(question) if question.present? }

  def self.key_for(question) = Digest::SHA256.hexdigest(I18n.transliterate(question.to_s).downcase.gsub(/[^a-z0-9]+/, " ").strip)

  def self.record(kind:, question:, user: nil, message: nil)
    create!(kind: kind, question: question.to_s.truncate(500), user: user, message: message)
  end

  # [{ question:, kind:, count:, last_at: }], the most asked first. The question shown is the latest one asked in that form.
  def self.ranked
    group(:question_key, :kind).order(Arel.sql("COUNT(*) DESC"), Arel.sql("MAX(created_at) DESC"))
      .pluck(Arel.sql("MAX(id)"), :kind, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))
      .map { |id, kind, count, last_at| { question: find(id).question, kind: kind, count: count, last_at: last_at } }
  end
end
