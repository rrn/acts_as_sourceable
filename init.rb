$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'active_record/acts/sourceable'
require 'active_record/acts/sourceable_site'
ActiveRecord::Base.send(:extend, ActiveRecord::Acts::Sourceable::ActMethod)