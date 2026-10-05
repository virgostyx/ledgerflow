# F13a: the mapping of the columns of a file to the fields of an import (and its reading options), kept under a name to be used again.
class ImportTemplate < ApplicationRecord
  acts_as_tenant :entity

  validates :name, presence: true, uniqueness: { scope: %i[entity_id kind] }
  validates :kind, inclusion: { in: Imports::Kind::KINDS }
end
