module ActsAsSourceable
  class Registry < ActiveRecord::Base
    self.table_name = 'acts_as_sourceable_registry'

    belongs_to :sourceable, :polymorphic => true
    validates_presence_of :sourceable_type, :sourceable_id

    def sources
       HoldingInstitution.find(self.holding_institution_ids) + Collection.find(self.collection_ids) + Item.find(self.item_ids)
    end
  end
end