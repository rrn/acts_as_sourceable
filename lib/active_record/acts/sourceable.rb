module ActiveRecord
  module Acts #:nodoc:
    module Sourceable #:nodoc:
      module ActMethod
        def acts_as_sourceable(options = {})
          # Include Class and Instance Methods
          extend ClassMethods unless (class << self; included_modules; end).include?(ClassMethods)
          include InstanceMethods unless included_modules.include?(InstanceMethods)

          has_many :sourceable_institutions, :as => :sourceable, :dependent => :destroy
          has_many :sources, :through => :sourceable_institutions, :source => :holding_institution

          named_scope :sourced, {:select => "DISTINCT #{table_name}.*", :joins => :sourceable_institutions}
          named_scope :unsourced, {:joins => "LEFT OUTER JOIN sourceable_institutions ON sourceable_institutions.sourceable_type = '#{class_name}' AND #{table_name}.id = sourceable_institutions.sourceable_id #{"LEFT OUTER JOIN flattened_item_#{table_name} ON #{table_name}.id = flattened_item_#{table_name}.#{table_name.singularize}_id" if column_names.include?('derived')}", :conditions => "sourceable_institutions.id IS NULL #{"AND #{table_name}.derived = false OR (#{table_name}.derived = true AND flattened_item_#{table_name}.id IS NULL)" if column_names.include?('derived')}"}

          after_save :record_source

          cattr_accessor :cache_flag
          self.cache_flag = options[:cache_flag]
          
          # Keep a list of all classes that are sourceable
          SourceableInstitution.sourceable_classes << self
        end

        module ClassMethods
          def garbage_collect
            # Destroy all entries of this class which no longer have a SourceableInstitution
            destroy_all("NOT EXISTS (SELECT * FROM sourceable_institutions WHERE sourceable_institutions.sourceable_type = '#{class_name}' AND sourceable_institutions.sourceable_id = #{table_name}.id)")
          end

          def unsource
            update_all("#{self.cache_flag} = false", ["holding_institution_id = ?", $HOLDING_INSTITUTION.id]) if self.cache_flag
          end
        end

        module InstanceMethods

          private
          
          def record_source
            if SourceableInstitution.record
              raise 'acts_as_sourceable cannot save because no global variable $INSTITUTION has been set for this conversion session.' if $HOLDING_INSTITUTION.nil?
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
  end
end
