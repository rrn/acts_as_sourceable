require 'acts_as_sourceable/acts_as_sourceable'
require 'acts_as_sourceable/registry'
require 'postgres_ext'

ActiveRecord::Base.extend ActsAsSourceable::ActMethod