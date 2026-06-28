module Accounting::Auditable
  extend ActiveSupport::Concern

  included do
    has_paper_trail meta: { entity_id: :entity_id }
  end
end
