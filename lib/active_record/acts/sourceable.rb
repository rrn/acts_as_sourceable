module ActiveRecord
  module Acts #:nodoc:
    module Sourceable #:nodoc:
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def acts_as_sourceable(options = {})
          
          class_eval <<-EOV
            include ActiveRecord::Acts::Sourceable::InstanceMethods

            has_many :sourceable_sites, :as => :sourceable
            has_many :sites, :through => :sourceable_sites

            after_save :record_source
          EOV
        end
      end

      module InstanceMethods
        private
        def record_source
          raise 'acts_as_sourceable cannot save because no global variable $SITE has been set for this conversion session.' if $SITE.nil?
          sourceable_site = SourceableSite.new
          sourceable_site.site = $SITE
          sourceable_site.sourceable = self
          sourceable_site.save!
        end
      end 
    end
  end
end
