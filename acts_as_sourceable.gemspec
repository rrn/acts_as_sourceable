Gem::Specification.new do |s|
  s.name = 'acts_as_sourceable'
  s.version = '2.1.6'
  s.date = %q{2013-03-07}
  s.email = 'technical@rrnpilot.org'
  s.homepage = 'http://github.com/rrn/acts_as_sourceable'
  s.summary = 'perform garbage collection on categories that are no longer referenced'
  s.description = 'Allows the RRN to perform garbage collection on categories that are no longer referenced.'
  s.authors = ['Nicholas Jakobsen', 'Ryan Wallace']
  s.require_paths = ["lib"]
  s.files = Dir.glob("{lib}/**/*") + %w(README.md)
end