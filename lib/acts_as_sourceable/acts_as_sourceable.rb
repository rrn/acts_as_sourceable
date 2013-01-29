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
          has_one :sourceable_institution, :class_name => 'ActsAsSourceable::Registry', :as => :sourceable, :dependent => :delete
          def sources; sourceable_institution.try(:sources) || []; end
        end
      end

      # CLASS SETUP
      extend ActsAsSourceable::ClassMethods

      # If a cache column is provided, use that to determine which records are sourced and unsourced
      # Elsif the records can be derived, we need to check the flattened item tables for any references
      # Else we check the sourceable_institutions to see if the record has a recorded source
      if options[:cache_column]
        scope :sourced, where(options[:cache_column] => true)
        scope :unsourced, where(options[:cache_column] => false)
      elsif options[:through]
        scope :sourced, joins(options[:through]).uniq
        scope :unsourced, joins("LEFT OUTER JOIN (#{sourced.to_sql}) sourced ON sourced.id = #{table_name}.id").where("sourced.id IS NULL")
      else
        scope :sourced, joins(:sourceable_institution)
        scope :unsourced, joins("LEFT OUTER JOIN (#{sourced.to_sql}) sourced ON sourced.id = #{table_name}.id").where("sourced.id IS NULL")
      end

      # Add a way of finding everything sourced by a particular set of records
      if options[:through]
        def sourced_by(*sources)
          raise NotImplementedError # TODO
        end
      else
        def sourced_by(*sources)
          holding_institution_ids, collection_ids, item_ids = ActsAsSourceable::HelperMethods.group_ids_by_class(sources)

          arel_table = ActsAsSourceable::Registry.arel_table
          h_contraint = arel_table[:holding_institution_ids].array_overlap(holding_institution_ids)
          c_contraint = arel_table[:collection_ids].array_overlap(collection_ids)
          i_contraint = arel_table[:item_ids].array_overlap(item_ids)

          sourced.where(h_contraint.or(c_contraint).or(i_contraint))
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
      scoping { ActsAsSourceable::Registry.where("sourceable_type = ? AND sourceable_id IN (#{@klass.select("#{@klass.table_name}.id").to_sql})", @klass.name).delete_all }
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
        self.class.sourced.exists?(self)
      end
    end

    def unsourced?
      !sourced?
    end

    # Add the given holding_institutions, collections, and items
    def add_sources(*sources)
      holding_institution_ids, collection_ids, item_ids = ActsAsSourceable::HelperMethods.group_ids_by_class(sources)
      registry = init_registry_entry
      set_sources(registry.holding_institution_ids + holding_institution_ids, registry.collection_ids + collection_ids, registry.item_ids + item_ids)
    end
    alias_method :add_source, :add_sources

    # Remove the given holding_institutions, collections, and items
    def remove_sources(*sources)
      holding_institution_ids, collection_ids, item_ids = ActsAsSourceable::HelperMethods.group_ids_by_class(sources)
      registry = init_registry_entry
      set_sources(registry.holding_institution_ids - holding_institution_ids, registry.collection_ids - collection_ids, registry.item_ids - item_ids)
    end
    alias_method :remove_source, :remove_sources

    # Record which holding_institution, collection, and optionally which item the record came from
    # If the record has no sources, the sourceable institution is deleted
    # NOTE: HoldingInstitutions are stored in the production database (so don't get any crazy ideas when refactoring this code)
    def set_sources(holding_institution_ids, collection_ids, item_ids)
      registry = init_registry_entry
      registry.holding_institution_ids = Array(holding_institution_ids).uniq
      registry.collection_ids = Array(collection_ids).uniq
      registry.item_ids = Array(item_ids).uniq

      if holding_institution_ids.any? || collection_ids.any? || item_ids.any?
        registry.save!
        set_sourceable_cache_column(true)
      elsif registry.persisted?
        registry.destroy
        set_sourceable_cache_column(false)
      end
    end
    
    private

    def init_registry_entry
      raise "Cannot set sources of a #{self.class.name}. They are sourced through #{acts_as_sourceable_options[:through]}" if acts_as_sourceable_options[:through]

      ActsAsSourceable::Registry.where(:sourceable_type => self.class.name, :sourceable_id => self.id).first_or_initialize
    end
    
    def set_sourceable_cache_column(value)
      update_column(acts_as_sourceable_options[:cache_column], value) if acts_as_sourceable_options[:cache_column] # Update via sql because we don't need callbacks and validations called
    end
  end

  module HelperMethods
    # Given an array of HoldingInstitutions, Collections, and Items, returns arrays containing only the records of each class.
    # Order of return arrays is [HoldingInstitutions, Collections, Items]
    def self.group_by_class(*sources)
      groups = Array(sources).flatten.group_by(&:class)
      return [groups[HoldingInstitution] || [], groups[Collection] || [], groups[Item] || []]
    end

    def self.group_ids_by_class(*sources)
      group_by_class(*sources).collect!{|group| group.collect(&:id)}
    end

    # Removes registry entries that no longer belong to a sourceable, item, collection, or holding institution
    def self.garbage_collect
      # Remove all registry entries where the sourceable is gone
      ActsAsSourceable::Registry.pluck(:sourceable_type).uniq.each do |sourceable_type|
        sourceable_table_name = sourceable_type.constantize.table_name
        sourceable_id_sql = ActsAsSourceable::Registry
          .select("#{ActsAsSourceable::Registry.table_name}.id")
          .where(:sourceable_type => sourceable_type)
          .joins("LEFT OUTER JOIN #{sourceable_table_name} ON #{sourceable_table_name}.id = #{ActsAsSourceable::Registry.table_name}.sourceable_id")
          .where("#{sourceable_table_name}.id IS NULL").to_sql

        ActsAsSourceable::Registry.delete_all("id IN (#{sourceable_id_sql})")
      end

      # Repair all Registry entries that reference missing items, collections, or holding institutions
      holding_institution_ids = HoldingInstitution.pluck(:id)
      collection_ids = Collection.pluck(:id)

      [:holding_institution, :collection, :item].each do |type|
        registries = ActsAsSourceable::Registry
        registries = registries.joins("LEFT OUTER JOIN #{type}s ON #{type}s.id = ANY(#{type}_ids)")
        registries = registries.group("#{ActsAsSourceable::Registry.table_name}.id")        
        # Having at least one listed source_id and no matching sources, or fewer matches than the total listed sources
        registries = registries.having("(array_length(#{type}_ids, 1) > 0 AND EVERY(#{type}s.id IS NULL)) OR count(*) < array_length(#{type}_ids, 1)")

        # Fix the registry entries that are wrong
        registries.includes(:sourceable).each do |registry|
          item_ids = Item.where(:id => registry.item_ids).pluck(:id)
          # ActiveRecord::Base.logger.debug "Registry #{registry.id}: holding_institution_ids: #{registry.holding_institution_ids.inspect} => #{registry.holding_institution_ids & holding_institution_ids}, collection_ids: #{registry.collection_ids.inspect} => #{registry.collection_ids & collection_ids}, item_ids: #{registry.item_ids.inspect} => #{registry.item_ids & item_ids} "
          registry.sourceable.set_sources(registry.holding_institution_ids & holding_institution_ids, registry.collection_ids & collection_ids, registry.item_ids & item_ids)
        end
      end
    end
  end
end