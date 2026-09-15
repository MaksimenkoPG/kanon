# frozen_string_literal: true

require_relative 'lib/kanon/version'

Gem::Specification.new do |spec|
  spec.name = 'kanon'
  spec.version = Kanon::VERSION
  spec.authors = ['Maksimenko Pavel']
  spec.email = ['pavel.g.maksimenko@gmail.com']

  spec.summary = 'A YAML config becomes a frozen tree of nodes, and declares the environment variables it needs'
  spec.description = <<~TEXT
    A YAML file becomes a frozen tree of nodes with dotted access, and the values
    that belong to the environment are declared in that same file. A read that
    misses a mandatory value fails naming every absent variable at once, and a
    typo in a key raises instead of returning nil. ERB tags keep working, so a
    file that already reads the environment that way needs no rewriting. The
    standard library only, with the config directory and the environment name
    injected from outside.
  TEXT

  spec.homepage = 'https://github.com/MaksimenkoPG/kanon'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |path|
      path.start_with?('spec/', 'script/', '.') || %w[Gemfile Rakefile].include?(path)
    end
  end
  spec.require_paths = ['lib']
end
