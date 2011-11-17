class SourceableInstitution < ActiveRecord::Base
  belongs_to :sourceable, :polymorphic => true
  belongs_to :holding_institution

  validates_presence_of :sourceable_type, :sourceable_id, :holding_institution_id
end