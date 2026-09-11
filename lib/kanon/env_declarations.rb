# frozen_string_literal: true

module Kanon
  class EnvDeclarations
    DECLARATION_KEYS = %i[env default type optional].freeze
    NAME_SEPARATOR = '_'
    USABLE_NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/.freeze

    private_constant :NAME_SEPARATOR, :USABLE_NAME

    def self.declaration?(value)
      return false unless value.is_a?(Hash)
      return true if value.key?(:env)

      value.keys.any? { |key| DECLARATION_KEYS.include?(key) } && (value.keys - DECLARATION_KEYS).empty?
    end

    def initialize(file_name, root_path = [])
      @file_name = file_name
      @root_path = root_path
    end

    def resolve(schema)
      resolved = walk_with(schema, ENV)
      raise MissingValue, "#{@file_name}.yml expects values from environment: #{@missing.join(', ')}" if @missing.any?

      resolved
    end

    def expected(schema)
      walk_with(schema, {})

      @taken.keys.to_h { |name| [name, @missing.include?(name)] }
    end

    def variable_name(path)
      usable((@root_path + path).map { |key| key.to_s.upcase }.join(NAME_SEPARATOR))
    end

    private

    def walk_with(schema, source)
      @source = source
      @missing = []
      @taken = {}

      walk(schema, []) { |node, path| resolve_leaf(node, path) }
    end

    def walk(node, path, &leaf)
      case node
      when Hash
        return leaf.call(node, path) if self.class.declaration?(node)

        node.each_with_object({}) { |(key, value), result| result[key] = walk(value, path + [key], &leaf) }
      when Array then node.each_with_index.map { |value, index| walk(value, path + [index], &leaf) }
      else leaf.call(node, path)
      end
    end

    def resolve_leaf(node, path)
      node.is_a?(Hash) ? resolve_declaration(node, path) : resolve_scalar(node, path)
    end

    def resolve_declaration(declaration, path)
      name = name_of(declaration, path)
      reject_unknown_keys(declaration, name)
      Typecast.reject_unknown_type(declaration[:type], name) if declaration.key?(:type)
      claim(name, path)

      value = value_of(name)
      resolved = cast(value.nil? ? declaration[:default] : value, declaration, name)
      return resolved unless resolved.nil?

      @missing << name if mandatory?(declaration)
      nil
    end

    # An empty value means "expected and not given", whatever produced the
    # emptiness: a tilde in the file, an ERB tag or a missing variable.
    def resolve_scalar(value, path)
      return value unless value.nil?

      name = variable_name(path)
      claim(name, path)
      resolved = value_of(name)
      return resolved unless resolved.nil?

      @missing << name
      nil
    end

    def name_of(declaration, path)
      declaration[:env] ? usable(declaration[:env].to_s) : variable_name(path)
    end

    def usable(name)
      return name if USABLE_NAME.match?(name)

      raise InvalidVariableName, "#{@file_name}.yml wants #{name.inspect}, which no shell can set as a variable"
    end

    def cast(value, declaration, name)
      return nil if value.nil?
      return Typecast.by_type_name(value, declaration[:type], name) if declaration.key?(:type)

      Typecast.like_sample(value, declaration[:default], name)
    end

    # The comparison is literal: the string 'false' from YAML is truthy in Ruby
    # and would otherwise switch the flag on.
    def mandatory?(declaration)
      declaration[:optional] != true
    end

    def claim(name, path)
      other = @taken[name]
      if other
        raise ConflictingVariable,
              "#{@file_name}.yml reads #{name} for both #{other.join('.')} and #{path.join('.')}"
      end

      @taken[name] = path
    end

    def value_of(name)
      raw = @source[name]
      raw.nil? || raw.empty? ? nil : raw
    end

    def reject_unknown_keys(declaration, name)
      unknown = declaration.keys - DECLARATION_KEYS
      return if unknown.empty?

      raise InvalidDeclaration,
            "#{@file_name}.yml declares #{name} with unsupported keys #{unknown.inspect}, " \
            "only #{DECLARATION_KEYS.inspect} are allowed"
    end
  end
end
