module ActsAsSourceable
  module ActMethod
    def acts_as_sourceable(options = {})
      options.assert_valid_keys :through, :cache_column, :used_by
      raise "Can't have a cache column and be sourced through an association" if options[:through] && options [:cache_column]
      class_attribute :acts_as_sourceable_options
      self.acts_as_sourceable_options = options

      # INSTANCE SETUP
      include ActsAsSourceable::InstanceMethods

      # If we get our sources through an association use that,
      # Else use the sourceable institutions table
      class_eval do
        if acts_as_sourceable_options[:through]
          def sources; send(acts_as_sourceable_options[:through]) || []; end
        else
          has_many :sourceable_registry_entries, :class_name => 'ActsAsSourceable::RegistryEntry', :as => :sourceable, :dependent => :delete_all
          def sources; self.sourceable_registry_entries.includes(:source).collect(&:source); end
        end
      end

      # CLASS SETUP
      extend ActsAsSourceable::ClassMethods

      # If a cache column is provided, use that to determine which records are sourced and unsourced
      # Elsif the records can be derived, we need to check the flattened item tables for any references
      # Else we check the registry_entries to see if the record has a recorded source
      if options[:cache_column]
        scope :sourced, where(options[:cache_column] => true)
        scope :unsourced, where(options[:cache_column] => false)
      elsif options[:through]
        scope :sourced, joins(options[:through]).group("#{table_name}.#{primary_key}") do
          include ActsAsSourceable::GroupScopeExtensions
        end
        scope :unsourced, joins("LEFT OUTER JOIN (#{sourced.to_sql}) sourced ON sourced.id = #{table_name}.id").where("sourced.id IS NULL")
      else
        scope :sourced, joins(:sourceable_registry_entries).group("#{table_name}.#{primary_key}") do
          include ActsAsSourceable::GroupScopeExtensions
        end
        scope :unsourced, joins("LEFT OUTER JOIN (#{ActsAsSourceable::RegistryEntry.select('sourceable_id AS id').where(:sourceable_type => self).to_sql}) sourced ON sourced.id = #{table_name}.id").where("sourced.id IS NULL")
      end

      # Add a way of finding everything sourced by a particular set of records
      if options[:through]
        def self.sourced_by(source)
          self.joins(acts_as_sourceable_options[:through]).where(reflect_on_association(acts_as_sourceable_options[:through]).table_name => {:id => source.id})
        end
      else
        def self.sourced_by(source)
          self.joins(:sourceable_registry_entries).where(ActsAsSourceable::RegistryEntry.table_name => {:source_type => source.class, :source_id => source.id}).uniq
        end
      end

      # Create a scope that returns record that is not used by the associations in options[:used_by]
      if options[:used_by]
        scope :unused, where(Array(options[:used_by]).collect {|usage_association| "#{table_name}.id NOT IN (" + select("#{table_name}.id").joins(usage_association).group("#{table_name}.id").to_sql + ")"}.join(' AND '))
        scope :orphaned, unsourced.unused
      else
        scope :orphaned, unsourced
      end

      # ACTIVE RELATION SETUP
      ActiveRecord::Relation.send(:include, ActsAsSourceable::ActiveRelationMethods)

      # Delegate the relation methods to the relation so we can call Klass.unsourced (do this in the metaclass because all these methods are class level)
      class << self
        delegate :add_sources, :add_source, :remove_source, :remove_sources, :unsource, :to => :scoped
      end
    end
  end
  
  module ActiveRelationMethods
    def remove_sources(*sources)
      scoping { @klass.find_each{|record| record.remove_sources(*sources) } }
    end
    alias_method :remove_source, :remove_sources

    def add_sources(*sources)
      scoping { @klass.find_each{|record| record.add_sources(*sources) } }
    end
    alias_method :add_source, :add_sources
    
    def unsource
      scoping { @klass.update_all("#{acts_as_sourceable_options[:cache_column]} = false", @klass.acts_as_sourceable_options[:cache_column] => true) } if @klass.acts_as_sourceable_options[:cache_column]
      scoping { ActsAsSourceable::RegistryEntry.where("sourceable_type = ? AND sourceable_id IN (#{@klass.select("#{@klass.table_name}.id").to_sql})", @klass.name).delete_all }
    end
  end

  module GroupScopeExtensions
    # Extension for scopes where we're grouping but want to be able to call count
    def count
      connection.select_value("SELECT count(1) FROM (#{to_sql}) AS count_all").to_i
    end
  end

  module ClassMethods
    def acts_like_sourceable?
      true
    end    
  end

  module InstanceMethods
    def acts_like_sourceable?
      true
    end
        
    def sourced?
      if acts_as_sourceable_options[:cache_column]
        self[acts_as_sourceable_options[:cache_column]]
      else
        self.class.sourced.uniq(false).exists?(self) # Remove the uniqness check because it allows for better use of the indexes
      end
    end

    def unsourced?
      !sourced?
    end

    # Add the given holding_institutions, collections, and items
    def add_sources(*sources)
      raise "Cannot set sources of a #{self.class.name}. They are sourced through #{acts_as_sourceable_options[:through]}" if acts_as_sourceable_options[:through]

      sources = Array(sources).flatten
      sources.each do |source|
        source_scope(source).first_or_create!
      end
      update_sourceable_cache_column(true) if sources.present?
    end
    alias_method :add_source, :add_sources

    # Remove the given holding_institutions, collections, and items
    def remove_sources(*sources)
      raise "Cannot set sources of a #{self.class.name}. They are sourced through #{acts_as_sourceable_options[:through]}" if acts_as_sourceable_options[:through]

      sources = Array(sources).flatten
      sources.each do |source|
        source_scope(source).delete_all
      end
      update_sourceable_cache_column(false) if self.sourceable_registry_entries.empty?
    end
    alias_method :remove_source, :remove_sources
    
    private

    def source_scope(source)
      ActsAsSourceable::RegistryEntry.where(:sourceable_type => self.class.name, :sourceable_id => self.id, :source_type => source.class, :source_id => source.id)
    end
 
    def update_sourceable_cache_column(value = nil)
      return unless acts_as_sourceable_options[:cache_column] # Update via sql because we don't need callbacks and validations called

      if value
        update_column(acts_as_sourceable_options[:cache_column], value)
      else
        update_column(acts_as_sourceable_options[:cache_column], sourceable_registry_entries.present?)
      end
    end
  end

  module HelperMethods
    # Removes registry entries that no longer belong to a sourceable, item, collection, or holding institution
    def self.garbage_collect
      # Remove all registry entries where the sourceable is gone
      ActsAsSourceable::RegistryEntry.pluck(:sourceable_type).uniq.each do |sourceable_type|
        sourceable_table_name = sourceable_type.constantize.table_name
        sourceable_id_sql = ActsAsSourceable::RegistryEntry
          .select("#{ActsAsSourceable::RegistryEntry.table_name}.id")
          .where(:sourceable_type => sourceable_type)
          .joins("LEFT OUTER JOIN #{sourceable_table_name} ON #{sourceable_table_name}.id = #{ActsAsSourceable::RegistryEntry.table_name}.sourceable_id")
          .where("#{sourceable_table_name}.id IS NULL").to_sql

        ActsAsSourceable::RegistryEntry.delete_all("id IN (#{sourceable_id_sql})")
      end

      # Remove all registry entries where the source is gone
      ActsAsSourceable::RegistryEntry.pluck(:source_type).uniq.each do |source_type|
        source_class = source_type.constantize
        source_table_name = source_class.table_name
        source_id_sql = ActsAsSourceable::RegistryEntry
          .select("#{ActsAsSourceable::RegistryEntry.table_name}.id")
          .where(:source_type => source_type)
          .joins("LEFT OUTER JOIN #{source_table_name} ON #{source_table_name}.id = #{ActsAsSourceable::RegistryEntry.table_name}.source_id")
          .where("#{source_table_name}.id IS NULL").to_sql

        sourceables = ActsAsSourceable::RegistryEntry.where("id IN (#{source_id_sql})").collect(&:sourceable)
        ActsAsSourceable::RegistryEntry.where("id IN (#{source_id_sql})").delete_all
        sourceables.each{|sourceable| sourceable.send(:update_sourceable_cache_column) }
      end
    end
  end
end