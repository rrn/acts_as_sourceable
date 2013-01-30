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
  t.belongs_to :source, :polymorphic => true
  t.timestamps
end

add_index :acts_as_sourceable_registry, [:sourceable_id, :sourceable_type], :name => :index_acts_as_sourceable_sourceables
add_index :acts_as_sourceable_registry, [:source_id, :source_type], :name => :index_acts_as_sourceable_sources

```

## Usage