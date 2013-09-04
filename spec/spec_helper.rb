$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')
require 'logger'
require 'active_record'
require 'acts_as_sourceable'

ActiveRecord::Base.logger = Logger.new(STDOUT)
ActiveRecord::Base.logger.level = Logger::INFO
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => ':memory:')

ActiveRecord::Schema.define(:version => 0) do

  create_table :acts_as_sourceable_registry, :force => true do |t|
    t.belongs_to :sourceable, :polymorphic => true
    t.belongs_to :source, :polymorphic => true
    t.timestamps
  end

  add_index :acts_as_sourceable_registry, [:sourceable_id, :sourceable_type], :name => :index_acts_as_sourceable_sourceables
  add_index :acts_as_sourceable_registry, [:source_id, :source_type], :name => :index_acts_as_sourceable_sources

  create_table :sourceable_records, :force => true do |t|
  end

  create_table :sourceable_through_records, :force => true do |t|
    t.belongs_to :item
  end

  create_table :cached_sourceable_records, :force => true do |t|
    t.belongs_to :item
    t.boolean :sourced, :null => false, :default => false
  end

  create_table :items, :force => true do |t|
    t.belongs_to :holding_institution
    t.belongs_to :collection
  end

  create_table :collections, :force => true do |t|
  end

  create_table :holding_institutions, :force => true do |t|
  end
end

class HoldingInstitution < ActiveRecord::Base
end

class Collection < ActiveRecord::Base
end

class Item < ActiveRecord::Base
  belongs_to :holding_institution
  belongs_to :collection
end

class SourceableRecord < ActiveRecord::Base
  acts_as_sourceable
end

class SourceableThroughRecord < ActiveRecord::Base
  belongs_to :item
  acts_as_sourceable :through => :item
end

class CachedSourceableRecord < ActiveRecord::Base
  acts_as_sourceable :cache_column => :sourced
end
