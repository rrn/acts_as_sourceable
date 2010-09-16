require 'acts_as_sourceable/sourceable_site'

module ActsAsSourceable
  module ActMethod
    def acts_as_sourceable(options = {})
      # Include Class and Instance Methods
      extend ClassMethods unless (class << self; included_modules; end).include?(ClassMethods)
      include InstanceMethods unless included_modules.include?(InstanceMethods)

      has_many :sourceable_sites, :as => :sourceable
      has_many :sources, :through => :sourceable_sites, :source => :site

      after_save :record_source

      # Keep a list of all classes that are sourceable
      SourceableSite.sourceable_classes << self
    end

    module ClassMethods
      def garbage_collect
        # Destroy all entries of this class which no longer have a SourceableSite
        destroy_all("NOT EXISTS (SELECT * FROM sourceable_sites WHERE sourceable_sites.sourceable_type = '#{class_name}' AND sourceable_sites.sourceable_id = #{table_name}.id)")
      end
    end

    module InstanceMethods

      private

      def record_source
        if SourceableSite.record
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
