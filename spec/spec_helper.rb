require 'pathname'
dir = Pathname(__FILE__).dirname
root = dir.join '..'
require root.join('init')

module Spec::Example::ExampleGroupMethods
  alias :context :describe
end

#Add in all the models, require them all here
dir = Pathname(__FILE__).parent.parent
relative = dir.join( 'models')
Dir.entries(relative).each do
  |entry|
  if File.extname(entry) == '.rb'
    require File.join(relative,entry)
  end
end

def connect
  config = YAML::load(IO.read(File.dirname(__FILE__)+ "/.." + '/config/database.yml'))
  ActiveRecord::Base.establish_connection(config)
end