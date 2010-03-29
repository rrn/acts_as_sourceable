module ActiveRecord
  module Acts #:nodoc:
    module Sourceable #:nodoc:
      module ActMethod
        def acts_as_sourceable(options = {})
          # Include Class and Instance Methods
          extend ClassMethods unless (class << self; included_modules; end).include?(ClassMethods)
          include InstanceMethods unless included_modules.include?(InstanceMethods)

          has_many :sourceable_institutions, :as => :sourceable
          has_many :sources, :through => :sourceable_institutions, :source => :holding_institution

          named_scope :sourced, {:joins => :sources}
          named_scope :unsourced, {:joins => "LEFT OUTER JOIN sourceable_institutions ON sourceable_institutions.sourceable_type = '#{class_name}' AND #{table_name}.id = sourceable_institutions.sourceable_id", :conditions => "sourceable_institutions.id IS NULL #{"AND #{table_name}.derived = false" if column_names.include?('derived')}"}
          
          after_save :record_source

          # Keep a list of all classes that are sourceable
          SourceableInstitution.sourceable_classes << self
        end

        module ClassMethods
          def garbage_collect
            # Destroy all entries of this class which no longer have a SourceableInstitution
            destroy_all("NOT EXISTS (SELECT * FROM sourceable_institutions WHERE sourceable_institutions.sourceable_type = '#{class_name}' AND sourceable_institutions.sourceable_id = #{table_name}.id)")
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
            end
          end
        end
      end
    end
  end
end
