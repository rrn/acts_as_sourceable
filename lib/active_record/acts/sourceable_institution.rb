class SourceableInstitution < ActiveRecord::Base

  belongs_to :sourceable, :polymorphic => true
  belongs_to :holding_institution

  validates_presence_of :sourceable_type, :sourceable_id, :holding_institution_id
  
  @@record = true # enables or disables automatic creation of SourceableInstitutions when a sourceable is saved
  @@sourceable_classes = Array.new
  cattr_reader :sourceable_classes
  cattr_accessor :record

  # No need to save a new entry if one already exists
  def save
    unless SourceableInstitution.exists?(:sourceable_type => sourceable_type, :sourceable_id => sourceable_id, :holding_institution_id => holding_institution_id)
      super
    end
  end
  
  def self.garbage_collect
    @@sourceable_classes.each do |sourceable_class|
      print "Garbage Collecting #{sourceable_class.name}..."
      sourceable_class.garbage_collect
      puts "done"
    end
  end
end
