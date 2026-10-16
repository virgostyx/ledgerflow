# B02c: what a person of the portal answered. An untrusted text (cleaned, limited) and a typed value; kept as it came. Written once: a question has one answer.
class Portal::Answer < ApplicationRecord
  MAX_BODY = 5_000

  belongs_to :question, class_name: "Portal::Question", inverse_of: :answer
  belongs_to :portal_user

  validates :body, length: { maximum: MAX_BODY }

  # What comes from outside is text, nothing else: no tag, no control character, no very long line. Shown escaped, kept cleaned.
  def self.clean(text)
    ActionController::Base.helpers.strip_tags(text.to_s).gsub(/[[:cntrl:]&&[^\n\t]]/, "").gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip.first(MAX_BODY)
  end
end
