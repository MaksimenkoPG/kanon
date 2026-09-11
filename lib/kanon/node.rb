# frozen_string_literal: true

module Kanon
  class Node
    def self.build(value)
      case value
      when Hash then new(value.each_with_object({}) { |(key, nested), result| result[key_for(key)] = build(nested) })
      when Array then value.map { |nested| build(nested) }.freeze
      else value
      end
    end

    def self.key_for(key)
      key.respond_to?(:to_sym) ? key.to_sym : key
    end
    private_class_method :key_for

    def initialize(values)
      @values = values.freeze
      reject_reserved_keys
      freeze
    end

    def [](key)
      @values.fetch(lookup_key(key)) { raise UnknownKey, "no key #{key} here, keys: #{keys.join(', ')}" }
    end

    def key?(key)
      @values.key?(lookup_key(key))
    end

    def keys
      @values.keys
    end

    def dig(*path)
      path.inject(self) do |level, key|
        case level
        when Node then level[key]
        when Array then dig_into_array(level, key)
        else raise UnknownKey, "no key #{key} inside a #{level.class}"
        end
      end
    end

    def to_h
      @values.each_with_object({}) { |(key, value), result| result[key] = self.class.unwrap(value) }
    end

    def self.unwrap(value)
      case value
      when Node then value.to_h
      when Array then value.map { |nested| unwrap(nested) }
      else value
      end
    end

    def ==(other)
      other.is_a?(Node) && to_h == other.to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end

    def inspect
      "#<Kanon::Node keys: #{keys.join(', ')}>"
    end

    def as_json(*)
      inspect
    end

    def to_json(*)
      require 'json'
      JSON.generate(as_json)
    end

    def encode_with(coder)
      coder.represent_scalar(nil, inspect)
    end

    def instance_variables
      []
    end

    def marshal_dump
      raise TypeError, "#{inspect} refuses serialization that would expose its values"
    end

    private

    def method_missing(name, *arguments)
      return @values[name] if arguments.empty? && @values.key?(name)

      raise NoMethodError, "undefined method `#{name}' for #{inspect}"
    end

    def respond_to_missing?(name, include_private = false)
      @values.key?(name.to_sym) || super
    end

    def dig_into_array(array, key)
      raise UnknownKey, "no index #{key} in an Array of #{array.size}" unless key.is_a?(Integer)

      array.fetch(key) { raise UnknownKey, "no index #{key} in an Array of #{array.size}" }
    end

    def lookup_key(key)
      key.respond_to?(:to_sym) ? key.to_sym : key
    end

    def reject_reserved_keys
      reserved = keys.select { |key| key.is_a?(Symbol) && self.class.method_defined?(key) }
      return if reserved.empty?

      raise ReservedKey, "#{reserved.join(', ')} clash with node methods and cannot be config keys"
    end
  end
end
