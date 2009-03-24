require 'rake'
require 'spec/rake/spectask'
require 'activerecord'
require 'yaml'

Spec::Rake::SpecTask.new(:spec => :migrate_schema) do |t|
  #Should really look in subdirectories as well and be recursive in some manner
  t.spec_files = FileList['spec/**/*_spec.rb']
  end

desc "Migrate Test schema to Database"
task :migrate_schema => :setup_db do
  puts "Loading Basic Testing Schema"
  load(File.dirname(__FILE__) + "/db/schema.rb") if File.exist?(File.dirname(__FILE__)+"/db/schema.rb")
end

desc "Connect to database"
task :setup_db do
  puts "Connecting to Database."
  config = YAML::load(IO.read(File.dirname(__FILE__)+ '/config/database.yml'))
  ActiveRecord::Base.establish_connection(config)
  puts "Connected."
end

task :default  => :spec do
end