# frozen_string_literal: true

require "pathname"

require_relative "tcxkit/version"
require_relative "tcxkit/error"
require_relative "tcxkit/limits"
require_relative "tcxkit/xml/clock"
require_relative "tcxkit/xml/element"
require_relative "tcxkit/xml/source"
require_relative "tcxkit/xml/parser"
require_relative "tcxkit/types"
require_relative "tcxkit/schema"
require_relative "tcxkit/field"
require_relative "tcxkit/message"
require_relative "tcxkit/message_builder"
require_relative "tcxkit/reader"

# A read-only, streaming parser for Garmin Training Center Database v2 files.
# See SPECIFICATION.md for the API and what each milestone delivers.
module TcxKit
  NAMESPACE = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  NAMESPACE_V1 = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v1"
  ACTIVITY_EXTENSION_NAMESPACE = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"
end
