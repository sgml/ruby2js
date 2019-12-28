# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)
require 'ruby2js/version'

Gem::Specification.new do |s|
  s.name = "ruby2js".freeze
  s.version = Ruby2JS::VERSION::STRING

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.require_paths = ["lib".freeze]
  s.authors = ["Sam Ruby".freeze]
  s.description = "    The base package maps Ruby syntax to JavaScript semantics.\n    Filters may be provided to add Ruby-specific or framework specific\n    behavior.\n".freeze
  s.email = "rubys@intertwingly.net".freeze
  s.files = %w(ruby2js.gemspec README.md) + Dir.glob("{lib}/**/*")
  s.homepage = "http://github.com/rubys/ruby2js".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 1.9.3".freeze)
  s.summary = "Minimal yet extensible Ruby to JavaScript conversion.".freeze

  if s.respond_to? :specification_version then
    s.specification_version = 4

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<parser>.freeze, [">= 0"])
    else
      s.add_dependency(%q<parser>.freeze, [">= 0"])
    end
  else
    s.add_dependency(%q<parser>.freeze, [">= 0"])
  end
end
