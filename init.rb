$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'active_record/acts/sourceable'
ActiveRecord::Base.class_eval { include ActiveRecord::Acts::Sourceable }
