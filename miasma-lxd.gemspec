$LOAD_PATH.unshift File.expand_path(File.dirname(__FILE__)) + '/lib/'
require 'miasma-lxd/version'
Gem::Specification.new do |s|
  s.name = 'miasma-lxd'
  s.version = MiasmaLxd::VERSION.version
  s.summary = 'Smoggy LXD API'
  s.author = 'Chris Roberts'
  s.email = 'code@chrisroberts.org'
  s.homepage = 'https://github.com/miasma-rb/miasma-lxd'
  s.description = 'Smoggy LXD API'
  s.license = 'Apache 2.0'
  s.require_path = 'lib'
  s.add_runtime_dependency 'http'
  s.add_development_dependency 'miasma', '>= 0.2.12'
  s.add_development_dependency 'pry'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'vcr'
  s.add_development_dependency 'webmock'
  s.add_development_dependency 'psych', '>= 2.0.8'
  s.add_runtime_dependency 'mime-types'
  s.files = Dir['lib/**/*'] + %w(miasma-lxd.gemspec README.md CHANGELOG.md LICENSE)
end
