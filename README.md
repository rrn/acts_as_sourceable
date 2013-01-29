# ActsAsSourceable

Allows the RRN to perform garbage project on categories that are no longer referenced.

## Installation

### In your gemfile
```ruby
gem 'acts_as_sourceable'
gem 'postgres_ext' # Currently, this needs to be included for the migration to work.
```

### Migration
```ruby
create_table :acts_as_sourceable_registry do |t|
  t.belongs_to :sourceable, :polymorphic => true
  t.integer :holding_institution_ids, :array => true, :default => []
  t.integer :collection_ids, :array => true, :default => []
  t.integer :item_ids, :array => true, :default => []
  t.timestamps
end

add_index :acts_as_sourceable_registry, [:sourceable_id, :sourceable_type], :name => :index_acts_as_sourceable_sourceables
add_index :acts_as_sourceable_registry, :holding_institution_ids, :name => :index_acts_as_sourceable_holding_institution_ids
add_index :acts_as_sourceable_registry, :collection_ids, :name => :index_acts_as_sourceable_collection_ids
add_index :acts_as_sourceable_registry, :item_ids, :name => :index_acts_as_sourceable_item_ids
```

## Usage