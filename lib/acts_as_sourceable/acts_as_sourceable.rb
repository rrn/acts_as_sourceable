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
        scope :sourced,   lambda { where(options[:cache_column] => true) }
        scope :unsourced, lambda { where(options[:cache_column] => false) }
      elsif options[:through]
        scope :sourced,   lambda { from(unscoped.joins(options[:through]).group("#{table_name}.#{primary_key}"), table_name) }
        scope :unsourced, lambda { readonly(false).joins("LEFT OUTER JOIN (#{sourced.to_sql}) sourced ON sourced.id = #{table_name}.id").where("sourced.id IS NULL") }
      else
        scope :sourced,   lambda { from(unscoped.joins(:sourceable_registry_entries).group("#{table_name}.#{primary_key}"), table_name) }
        scope :unsourced, lambda { readonly(false).joins("LEFT OUTER JOIN (#{ActsAsSourceable::RegistryEntry.select('sourceable_id AS id').where(:sourceable_type => self.klass.name).to_sql}) sourced ON sourced.id = #{table_name}.id").where("sourced.id IS NULL") }
      end

      # Add a way of finding everything sourced by a particular set of records
      if options[:through]
        scope :sourced_by, lambda { |source| readonly(false).joins(options[:through]).where(reflect_on_association(options[:through]).table_name => {:id => source.id}) }
      else
        scope :sourced_by, lambda { |source| readonly(false).joins(:sourceable_registry_entries).where(ActsAsSourceable::RegistryEntry.table_name => {:source_type => source.class.name, :source_id => source.id}).distinct }
      end

      # Create a scope that returns record that is not used by the associations in options[:used_by]
      if options[:used_by]
        scope :unused,   lambda { where(Array(options[:used_by]).collect {|usage_association| "#{table_name}.id NOT IN (" + select("#{table_name}.id").joins(usage_association).group("#{table_name}.id").to_sql + ")"}.join(' AND ')) }
        scope :used,     lambda { where(Array(options[:used_by]).collect {|usage_association| "#{table_name}.id IN (" + select("#{table_name}.id").joins(usage_association).group("#{table_name}.id").to_sql + ")"}.join(' OR ')) }
        scope :orphaned, lambda { unsourced.unused }
      else
        scope :orphaned, lambda { unsourced }
      end
    end
  end

  module ClassMethods
    def acts_like_sourceable?
      true
    end

    def remove_sources(*sources)
      find_each{|record| record.remove_sources(*sources) }
    end
    alias_method :remove_source, :remove_sources

    def add_sources(*sources)
      find_each{|record| record.add_sources(*sources) }
    end
    alias_method :add_source, :add_sources

    def unsource
      # OPTIMIZATION: it's faster to only set the cache column to false if it is true instead of setting all to false indiscriminately
      where(acts_as_sourceable_options[:cache_column] => true).update_all(acts_as_sourceable_options[:cache_column] => false) if acts_as_sourceable_options[:cache_column]
      ActsAsSourceable::RegistryEntry.where(:sourceable_type => self.name, :sourceable_id => self.all).delete_all
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

    def used?
      acts_as_sourceable_options[:used_by].any?{|association| send(association).present? }
    end

    def unused?
      !used?
    end

    def usages
      Hash[acts_as_sourceable_options[:used_by].collect{|association| [association, send(association)] }]
    end

    # Add the given holding_institutions, collections, and items
    def add_sources(*sources)
      raise "Cannot set sources of a #{self.class.name}. They are sourced through #{acts_as_sourceable_options[:through]}" if acts_as_sourceable_options[:through]

      sources = Array(sources).flatten
      sources.each do |source|
        entry = source_registry_entries(source).first_or_initialize
        # touch existing RegistryEntry to keep track of "freshness" of the sourcing
        entry.persisted? ? entry.touch : entry.save!
      end
      update_sourceable_cache_column(true) if sources.present?
    end
    alias_method :add_source, :add_sources

    # Remove the given holding_institutions, collections, and items
    def remove_sources(*sources)
      raise "Cannot set sources of a #{self.class.name}. They are sourced through #{acts_as_sourceable_options[:through]}" if acts_as_sourceable_options[:through]

      sources = Array(sources).flatten
      sources.each do |source|
        source_registry_entries(source).delete_all
      end
      update_sourceable_cache_column(false) if self.sourceable_registry_entries.empty?
    end
    alias_method :remove_source, :remove_sources

    private

    def source_registry_entries(source)
      sourceable_registry_entries.where(:source_type => source.class.name, :source_id => source.id)
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
      ActsAsSourceable::RegistryEntry.distinct.pluck(:sourceable_type).each do |sourceable_type|
        sourceable_table_name = sourceable_type.constantize.table_name
        sourceable_id_sql = ActsAsSourceable::RegistryEntry
          .select("#{ActsAsSourceable::RegistryEntry.table_name}.id")
          .where(:sourceable_type => sourceable_type)
          .joins("LEFT OUTER JOIN #{sourceable_table_name} ON #{sourceable_table_name}.id = #{ActsAsSourceable::RegistryEntry.table_name}.sourceable_id")
          .where("#{sourceable_table_name}.id IS NULL").to_sql

        ActsAsSourceable::RegistryEntry.where("id IN (#{sourceable_id_sql})").delete_all
      end

      # Remove all registry entries where the source is gone
      ActsAsSourceable::RegistryEntry.distinct.pluck(:source_type).each do |source_type|
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
