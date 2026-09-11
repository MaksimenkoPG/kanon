# frozen_string_literal: true

module Kanon
  class Document
    KEYWORD_SAFE_LOAD = YAML.method(:safe_load).parameters.any? { |kind, name| kind == :key && name == :aliases }

    def initialize(directory, file_name, environment)
      @directory = directory
      @file_name = file_name
      @environment = environment
    end

    def schema
      narrowed = narrow_to_current_env(symbolized)

      split_root(narrowed.nil? ? {} : narrowed)
    end

    private

    def symbolized
      deep_symbolize(parse(evaluate_erb(read_file)))
    rescue SystemStackError
      raise InvalidSource, "#{@file_name}.yml is nested too deeply to read or refers to itself through an alias",
            cause: nil
    end

    def read_file
      unless @file_name.to_s.match?(/\A[a-z0-9_]+\z/)
        raise FileMissing,
              "#{@file_name.inspect} is not a bare configuration file name"
      end

      path = File.join(@directory, "#{@file_name}.yml")
      raise FileMissing, "No such configuration file: #{path}" unless File.exist?(path)

      File.read(path)
    rescue SystemCallError => e
      raise InvalidSource, "#{@file_name}.yml cannot be opened: #{e.class}", cause: nil
    end

    # Only the error class reaches the message: the original text carries the
    # value of an environment variable into logs and exception mail.
    def evaluate_erb(text)
      ERB.new(text).result
    rescue StandardError, ScriptError => e
      raise InvalidSource, "#{@file_name}.yml failed while running ERB: #{e.class}", cause: nil
    end

    def parse(text)
      loaded = if KEYWORD_SAFE_LOAD
                 YAML.safe_load(text, permitted_classes: [Symbol], aliases: true)
               else
                 YAML.safe_load(text, [Symbol], [], true)
               end
      loaded || {}
    rescue Psych::SyntaxError => e
      raise InvalidSource, "#{@file_name}.yml is not valid YAML: #{e.message}", cause: nil
    rescue Psych::DisallowedClass => e
      raise InvalidSource, "#{@file_name}.yml holds a YAML type the loader does not accept: #{e.message}",
            cause: nil
    rescue Psych::Exception => e
      raise InvalidSource, "#{@file_name}.yml cannot be built into a document: #{e.message}", cause: nil
    end

    def narrow_to_current_env(node)
      return node unless node.is_a?(Hash) && node.key?(@environment.to_sym)

      node.fetch(@environment.to_sym)
    end

    def split_root(node)
      return [[@file_name], node] if node.is_a?(Array)
      return [[], node] unless node.is_a?(Hash) && node.size == 1 && node.values.first.is_a?(Hash) &&
                               !Kanon::EnvDeclarations.declaration?(node.values.first)

      [[node.keys.first], node.values.first]
    end

    def deep_symbolize(node)
      case node
      when Hash then symbolize_keys(node)
      when Array then node.map { |value| deep_symbolize(value) }
      else node
      end
    end

    def symbolize_keys(node)
      seen = {}
      node.each_with_object({}) do |(key, value), result|
        name = key.respond_to?(:to_sym) ? key.to_sym : key
        reject_twin(seen[name], key) if seen.key?(name)

        seen[name] = key
        result[name] = deep_symbolize(value)
      end
    end

    def reject_twin(first, second)
      raise InvalidSource, "#{@file_name}.yml reads #{first.inspect} and #{second.inspect} as one key"
    end
  end
end
