Gem::Specification.new do |s|
  s.name = 'acts_as_sourceable'
  s.version = '1.0.0'
  s.date = %q{2010-09-16}
  s.email = 'technical@rrnpilot.org'
  s.homepage = 'http://github.com/rrn/acts_as_sourceable'
  s.summary = 'Allows the RRN to perform garbage collection on categories that are no longer referenced.'
  s.authors = ['Nicholas Jakobsen', 'Ryan Wallace']
  s.extra_rdoc_files = ['README.rdoc']
  s.has_rdoc = true
  
  s.add_dependency 'acts_as_replaceable'
end