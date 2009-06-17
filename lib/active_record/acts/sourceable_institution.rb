class SourceableInstitution < ActiveRecord::Base
  #Tristan: Ugly hack until someone takes the replaceable out of the sourceable, plugins are standalone, son!
  if defined?(RAILS_ENV)
    acts_as_replaceable :conditions => [:sourceable_type, :sourceable_id, :holding_institution_id]
  end
  belongs_to :sourceable, :polymorphic => true
  belongs_to :holding_institution

  validates_presence_of :sourceable_type, :sourceable_id, :holding_institution_id
  
  @@record = true # enables or disables automatic creation of SourceableInstitutions when a sourceable is saved
  @@sourceable_classes = Array.new
  cattr_reader :sourceable_classes
  cattr_accessor :record
  
  def self.garbage_collect
    @@sourceable_classes.each do |sourceable_class|
      print "Garbage Collecting #{sourceable_class.name}..."
      sourceable_class.garbage_collect
      puts "done"
    end
  end
end
