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

      named_scope :sourced, {:select => "DISTINCT #{table_name}.*", :joins => :sourceable_institutions}
      
      # An sourceable is unsourced if it has no sourceable_institution
      # OR if the sourceable is derived, it is unsourced if it doesn't 
      # have an entry in the corresponding flattened_item table.
      named_scope :unsourced, {:select => "DISTINCT #{table_name}.*", 
                               :joins => "LEFT OUTER JOIN sourceable_institutions ON sourceable_institutions.sourceable_type = '#{name}' AND #{table_name}.id = sourceable_institutions.sourceable_id #{"LEFT OUTER JOIN flattened_item_#{table_name} ON #{table_name}.id = flattened_item_#{table_name}.#{table_name.singularize}_id" if column_names.include?('derived')}",
                               :conditions => "sourceable_institutions.id IS NULL #{"AND #{table_name}.derived = false OR (#{table_name}.derived = true AND flattened_item_#{table_name}.id IS NULL)" if column_names.include?('derived')}"}

      after_save :record_source

      if options[:uses]
        cattr_accessor :uses
        self.uses = options[:uses]

        named_scope :unused, {:joins => unused_joins(options[:uses]), :conditions => unused_conditions(options[:uses])}
      end

      cattr_accessor :cache_flag
      self.cache_flag = options[:cache_flag]
      
      # Keep a list of all classes that are sourceable
      SourceableInstitution.sourceable_classes << self
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
        update_all("#{self.cache_flag} = false", ["holding_institution_id = ?", $HOLDING_INSTITUTION.id]) if self.cache_flag
      end
    end

    module InstanceMethods
      def unsourced?
        self.class.unsourced.exists?(self)
      end
        
      private
      
      def record_source
        if SourceableInstitution.record
          raise 'acts_as_sourceable cannot save because no global variable $HOLDING_INSTITUTION has been set for this conversion session.' if $HOLDING_INSTITUTION.nil?
          sourceable_institution = SourceableInstitution.new
          sourceable_institution.holding_institution = $HOLDING_INSTITUTION
          sourceable_institution.sourceable = self
          sourceable_institution.save

          self.class.update_all("#{self.class.cache_flag} = true", ["id = ?", id]) if self.class.cache_flag
        end
      end
    end
  end
end

if Object.const_defined?("ActiveRecord")
  ActiveRecord::Base.send(:include, ActsAsSourceable)
end
