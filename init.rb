$:.unshift "#{File.dirname(__FILE__)}/lib"
require 'active_record'
require 'active_record/acts/sourceable'
require 'active_record/acts/sourceable_institution'
ActiveRecord::Base.send(:extend, ActiveRecord::Acts::Sourceable::ActMethod)
  