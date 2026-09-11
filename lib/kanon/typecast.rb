# frozen_string_literal: true

module Kanon
  module Typecast
    TRUE_VALUES = %w[1 true yes on].freeze
    FALSE_VALUES = %w[0 false no off].freeze
    TYPE_NAMES = %w[string integer float boolean list].freeze

    private_constant :TRUE_VALUES, :FALSE_VALUES

    module_function

    def like_sample(raw_value, sample, source)
      case sample
      when true, false then boolean(raw_value, source)
      when Integer then integer(raw_value, source)
      when Float then float(raw_value, source)
      when Array then list(raw_value)
      else raw_value
      end
    end

    def by_type_name(raw_value, type_name, source)
      reject_unknown_type(type_name, source)

      case type_name.to_s
      when 'string' then raw_value.to_s
      when 'integer' then integer(raw_value, source)
      when 'float' then float(raw_value, source)
      when 'boolean' then boolean(raw_value, source)
      when 'list' then list(raw_value)
      end
    end

    def reject_unknown_type(type_name, source)
      return if TYPE_NAMES.include?(type_name.to_s)

      raise InvalidValue, "#{source} declares unknown type #{type_name.inspect}"
    end

    def boolean(raw_value, source)
      return true if TRUE_VALUES.include?(raw_value.to_s.downcase)
      return false if FALSE_VALUES.include?(raw_value.to_s.downcase)

      raise InvalidValue,
            "#{source} must be one of #{(TRUE_VALUES + FALSE_VALUES).join(', ')}, got #{describe(raw_value)}"
    end

    # A list that leaves no items counts as no value, so a mandatory one fails
    # rather than arriving empty.
    def list(raw_value)
      return raw_value if raw_value.is_a?(Array)

      items = raw_value.to_s.split(',').map(&:strip).reject(&:empty?)
      items.empty? ? nil : items
    end

    def describe(raw_value)
      "#{raw_value.class} of #{raw_value.to_s.length} characters"
    end

    # The base is explicit: without it a leading zero would be read as octal, and
    # port 010 would turn into 8.
    def integer(raw_value, source)
      raw_value.is_a?(Integer) ? raw_value : Integer(raw_value.to_s, 10)
    rescue ArgumentError, TypeError
      raise InvalidValue, "#{source} must be an integer, got #{describe(raw_value)}", cause: nil
    end

    def float(raw_value, source)
      Float(raw_value)
    rescue ArgumentError, TypeError
      raise InvalidValue, "#{source} must be a number, got #{describe(raw_value)}", cause: nil
    end
  end
end
