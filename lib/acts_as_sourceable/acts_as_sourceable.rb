module ActsAsSourceable
  module ActMethod
    def acts_as_sourceable(options = {})
      # Include Class and Instance Methods
      ActiveRecord::Relation.send(:include, ActsAsSourceable::ActiveRelationMethods)
      extend ActsAsSourceable::ClassMethods
      include ActsAsSourceable::InstanceMethods

      has_many :sourceable_institutions, :as => :sourceable, :dependent => :destroy
      has_many :sources, :through => :sourceable_institutions, :source => :holding_institution
      
      # Delegate the relation methods to the relation
      class << self
        delegate :update_sources, :unsource, :to => :scoped
      end

      class_attribute :sourceable_cache_column, :sourceable_used_by, :sourceable_sourced_by
      self.sourceable_cache_column = options[:cache_column]
      self.sourceable_used_by = options[:used_by]
      self.sourceable_sourced_by = options[:sourced_by]
      
      # If a cache column is provided, use that to determine which records are sourced and unsourced
      # Elsif the records can be derived, we need to check the flattened item tables for any references
      # Else we check the sourceable_institutions to see if the record has a recorded source
      if sourceable_cache_column
        scope :sourced, where(sourceable_cache_column => true)
        scope :unsourced, where(sourceable_cache_column => false)
      else
        scope :sourced, joins(:sourceable_institutions).group("#{table_name}.id")
        scope :unsourced, joins("LEFT OUTER JOIN sourceable_institutions ON sourceable_id = #{quoted_table_name}.id and sourceable_type = '#{self.name}'").where("sourceable_id IS NULL")
      end

      # Create a scope that returns record that is not used by the associations in sourceable_used_by
      if sourceable_used_by
        scope :unused, where(Array(sourceable_used_by).collect {|usage_association| "id NOT IN (" + select("#{table_name}.id").joins(usage_association).group("#{table_name}.id").to_sql + ")"}.join(' AND '))
        scope :orphaned, unsourced.unused
      else
        scope :orphaned, unsourced
      end
    end
  end
  
  module ActiveRelationMethods
    def update_sources
      scoping { @klass.find_each(&:update_sources) }
    end
    
    def unsource
      scoping { @klass.update_all("#{sourceable_cache_column} = false", @klass.sourceable_cache_column => true) } if @klass.sourceable_cache_column
      scoping { SourceableInstitution.where("sourceable_type = ? AND sourceable_id IN (#{@klass.select(:id).to_sql})", @klass.name).delete_all }
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
    
    # Automatically update the sources for this model
    # If the model gets its sources from another model, collect the sources of that model and record them as your own
    # Else, this model must belong to a holding institution, so that is the source
    def update_sources
      if sourceable_sourced_by
        if self.class.reflect_on_association(sourceable_sourced_by.to_sym).collection?
          source_id_sql = send(sourceable_sourced_by).joins(:sourceable_institutions).select("sourceable_institutions.holding_institution_id").to_sql
          sources = HoldingInstitution.where("id IN (#{source_id_sql})")
          set_sources(sources)
        else
          set_sources(send(sourceable_sourced_by).sources)
        end
      else
        set_sources(holding_institution)
      end
    end
    
    def sourced?
      if sourceable_cache_column
        self[sourceable_cache_column]
      else
        self.class.sourced.exists?(self)
      end
    end

    def unsourced?
      !sourced?
    end

    # NOTE: We do a much more verbose method of assigning sources than the obvious self.sources = Array(holding_institutions)
    #       because HoldingInstitutions are present in the production database, and assigning sources causes rails to use the
    #       production database (as opposed to the conversion database) to check for existing sources. This is obviously bad
    #       because the sources in the production database do not reflect those that are in the conversion database since we
    #       unsource many things during conversion.
    def set_sources(holding_institutions)
      holding_institution_ids = Array(holding_institutions).collect(&:id)
      existing_source_ids = sourceable_institutions.pluck('holding_institution_id')
      
      # Delete those that have been removed
      condition = holding_institution_ids.any? ? ["holding_institution_id NOT IN (?)", existing_source_ids] : nil # Can't use "NOT IN (?)" for an empty array because the result is always false
      SourceableInstitution.where(:sourceable_type => self.class.name, :sourceable_id => self.id).delete_all(condition)
      
      # Add those that are not present
      holding_institution_ids.each do |holding_institution_id|
        self.sourceable_institutions << SourceableInstitution.new(:holding_institution_id => holding_institution_id) unless existing_source_ids.include?(holding_institution_id)
      end
      
      set_sourceable_cache_column(holding_institution_ids.any?)
    end
    
    private
    
    def set_sourceable_cache_column(value)
      # Update via sql because we don't need callbacks and validations called 
      self.class.update_all({sourceable_cache_column => value}, :id => id) if sourceable_cache_column
    end
  end
end