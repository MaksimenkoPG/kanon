# frozen_string_literal: true

module Kanon
  class Error < StandardError; end
  class FileMissing < Error; end
  class InvalidSource < Error; end
  class EmptyDirectory < Error; end
  class EmptyEnvironment < Error; end
  class InvalidDeclaration < Error; end
  class InvalidVariableName < Error; end
  class MissingValue < Error; end
  class InvalidValue < Error; end
  class ReservedKey < Error; end
  class ConflictingVariable < Error; end
  class UnknownKey < Error; end
end
