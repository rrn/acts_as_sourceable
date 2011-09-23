require 'acts_as_sourceable/sourceable_institution'

module ActsAsSourceable
  def self.included(base)
    base.extend(ActMethod)
  end
  
  module ActMethod
    def acts_as_sourceable(options = {})
      # Include Class and Instance Methods
      extend ClassMethods unless (class << self; included_modules; end).include?(ClassMethods)
      include InstanceMethods unless included_modules.include?(InstanceMethods)

      has_many :sourceable_institutions, :as => :sourceable, :dependent => :destroy
      has_many :sources, :through => :sourceable_institutions, :source => :holding_institution
      
      after_save :record_source
      cattr_accessor :sourced_cache_column

      self.sourced_cache_column = options[:cache_column]
      unused_unless(*options[:uses]) if options[:uses]

      # If a cache column is provided, use that to determine which records are sourced and unsourced
      # Elsif the records can be derived, we need to check the flattened item tables for any references
      # Else we check the sourceable_institutions to see if the record has a recorded source
      if sourced_cache_column
        scope :sourced, where(sourced_cache_column => true)
        scope :unsourced, where(sourced_cache_column => false)
      elsif column_names.include?('derived')
        scope :sourced, where("id IN (#{select("#{quoted_table_name}.id").joins(:"flattened_item_#{table_name}").group("#{quoted_table_name}.id").to_sql})")
        scope :unsourced, joins("LEFT OUTER JOIN flattened_item_#{table_name} ON #{table_name.singularize}_id = #{quoted_table_name}.id").where("#{table_name.singularize}_id IS NULL")
      else
        scope :sourced, where("id IN (#{select("#{quoted_table_name}.id").joins(:sourceable_institutions).group("#{quoted_table_name}.id").to_sql})")
        scope :unsourced, joins("LEFT OUTER JOIN sourceable_institutions ON sourceable_id = #{quoted_table_name}.id and sourceable_type = '#{self.name}'").where("sourceable_id IS NULL")
      end
      
      # Keep a list of all classes that are sourceable
      #
      # FIXME: This only works because sourceable_classes is pass by reference
      # so we read it and then we add an element to it. Try to find a less hackish
      # way to do this.
      SourceableInstitution.sourceable_classes << self unless SourceableInstitution.sourceable_classes.include?(self)
    end
    
    def unused_unless(*args)
      cattr_accessor :uses
      self.uses = args

      scope :unused, joins(unused_joins(self.uses)).where(unused_conditions(self.uses))
    end

    def unused_joins(uses)
      uses.collect do |use|
        case use
        when 'items'
          "LEFT OUTER JOIN flattened_item_#{table_name} AS items ON items.#{table_name.singularize}_id = #{table_name}.id"
        when 'user_submissions'
          "LEFT OUTER JOIN user_submissions ON user_submissions.user_submittable_type = '#{name}' AND user_submissions.user_submittable_id = #{table_name}.id"
        when 'discussions'
          "LEFT OUTER JOIN discussions ON discussions.discussable_type = '#{name}' AND discussions.discussable_id = #{table_name}.id"
        when 'alternate_names'
          "LEFT OUTER JOIN alternate_names ON alternate_names.alternate_nameable_type = '#{name}' AND alternate_names.alternate_nameable_id = #{table_name}.id"
        when 'project_items'
          "LEFT OUTER JOIN project_items ON project_items.item_id = #{table_name}.id"
        when 'languages'
          "LEFT OUTER JOIN languages ON languages.culture_id = cultures.id"
        end
      end
    end

    def unused_conditions(uses)
      conditions_hash = {}
      
      uses.each do |use|
        conditions_hash[use] = {:id => nil}
      end

      return conditions_hash
    end
    
    module ClassMethods
      def garbage_collect
        # Destroy all entries of this class which no longer have a SourceableInstitution
        destroy_all("NOT EXISTS (SELECT * FROM sourceable_institutions WHERE sourceable_institutions.sourceable_type = '#{name}' AND sourceable_institutions.sourceable_id = #{table_name}.id)")
      end

      def unsource
        update_all("#{sourced_cache_column} = false", :holding_institution_id => $HOLDING_INSTITUTION.id, sourced_cache_column => true) if sourced_cache_column
      end      
    end

    module InstanceMethods
      def sourced?
        if sourced_cache_column
          self[sourced_cache_column]
        else
          self.class.sourced.exists?(self)
        end
      end
      
      def unsourced?
        !sourced?
      end
        
      private
      
      def record_source
        if SourceableInstitution.record
          raise 'acts_as_sourceable cannot save because no global variable $HOLDING_INSTITUTION has been set for this conversion session.' if $HOLDING_INSTITUTION.nil?
          
          # add the holding institution as a source if it isn't already
          self.sources << $HOLDING_INSTITUTION unless sourceable_institutions.exists?(:holding_institution_id => $HOLDING_INSTITUTION.id)

          # Update via sql because we don't need callbacks and validations called 
          self.class.update_all("#{sourced_cache_column} = true", :id => id) if sourced_cache_column
        end
      end
    end
  end
end

if Object.const_defined?("ActiveRecord")
  ActiveRecord::Base.send(:include, ActsAsSourceable)
end
