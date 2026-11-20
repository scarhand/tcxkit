# frozen_string_literal: true

require_relative "tcxkit/version"
require_relative "tcxkit/error"

# A read-only, streaming parser for Garmin Training Center Database v2 files.
# See SPECIFICATION.md for the planned API; the reader arrives in milestone M1.
module TcxKit
  NAMESPACE = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  ACTIVITY_EXTENSION_NAMESPACE = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"
end
