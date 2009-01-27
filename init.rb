$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'active_record/acts/sourceable'
require 'active_record/acts/sourceable_site'

ActiveRecord::Base.class_eval do
  include ActiveRecord::Acts::Sourceable
end
