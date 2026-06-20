# frozen_string_literal: true

# Third-party dependencies must load before the metrics module: NumericResult
# mixes in ActionView helpers and metrics use ActiveSupport durations at
# definition time.
require "pay"
require "active_support/time"
require "active_support/core_ext/numeric/conversions"
require "active_support/core_ext/string/filters"
require "action_view"

require_relative "profitable/version"
require_relative "profitable/error"
require_relative "profitable/engine"
require_relative "profitable/mrr_calculator"
require_relative "profitable/numeric_result"
require_relative "profitable/json_helpers"
require_relative "profitable/metrics"
