# frozen_string_literal: true

require 'monitor'
require 'yaml'
require 'erb'
require_relative 'kanon/version'
require_relative 'kanon/errors'
require_relative 'kanon/document'
require_relative 'kanon/node'
require_relative 'kanon/typecast'
require_relative 'kanon/env_declarations'

module Kanon
  DEFAULT_DIRECTORY = 'config'
  DEFAULT_ENVIRONMENT = 'development'
  ENVIRONMENT_VARIABLES = %w[APP_ENV RAILS_ENV RACK_ENV].freeze

  @monitor = Monitor.new
  @storage = {}

  class << self
    def directory
      @monitor.synchronize { @directory ||= DEFAULT_DIRECTORY }
    end

    def directory=(path)
      raise EmptyDirectory, 'configuration directory cannot be empty' if blank?(path)

      @monitor.synchronize do
        @directory = path.to_s.strip
        clear
      end
    end

    def environment
      @monitor.synchronize { @environment ||= given_environment || DEFAULT_ENVIRONMENT }
    end

    def environment=(name)
      raise EmptyEnvironment, 'environment name cannot be empty' if blank?(name)

      @monitor.synchronize do
        @environment = name.to_s.strip
        clear
      end
    end

    def read_config(file_name)
      data = build(file_name.to_s.to_sym)
      data = { file_name.to_s.to_sym => data } unless data.is_a?(Hash)

      Kanon::Node.build(data)
    end

    def [](file_name)
      load_config(file_name)
    end

    def load_config(file_name)
      name = file_name.to_s.to_sym

      @monitor.synchronize { @storage[name] ||= read_config(name) }
    end

    def load_configs(*file_names)
      file_names.to_h { |file_name| [file_name.to_s.to_sym, load_config(file_name)] }
    end

    def loaded_files
      @monitor.synchronize { @storage.keys }
    end

    def expected_variables(file_name)
      declarations, schema = prepare(file_name.to_s.to_sym)

      declarations.expected(schema)
    end

    private

    def clear
      @monitor.synchronize { @storage.clear }
    end

    def given_environment
      ENVIRONMENT_VARIABLES.map { |name| ENV.fetch(name, nil) }.find { |value| !blank?(value) }&.strip
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def build(file_name)
      declarations, schema = prepare(file_name)

      deep_freeze(declarations.resolve(schema))
    end

    def prepare(file_name)
      prefix, schema = Kanon::Document.new(directory, file_name, environment).schema

      [Kanon::EnvDeclarations.new(file_name, prefix), schema]
    end

    def deep_freeze(value)
      case value
      when Hash then value.each_value { |nested| deep_freeze(nested) }.freeze
      when Array then value.each { |nested| deep_freeze(nested) }.freeze
      else value.freeze
      end
    end
  end
end
