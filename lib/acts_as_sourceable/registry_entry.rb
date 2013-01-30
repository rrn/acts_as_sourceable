module ActsAsSourceable
  class RegistryEntry < ActiveRecord::Base
    self.table_name = 'acts_as_sourceable_registry'

    belongs_to :sourceable, :polymorphic => true
    belongs_to :source, :polymorphic => true
    validates_presence_of :sourceable_type, :sourceable_id, :source_type, :source_id
  end
end