# frozen_string_literal: true

# Third-party dependencies must load first: NumericResult and the metrics
# module mix in ActionView helpers and use ActiveSupport durations at
# definition time, so the gem cannot rely on the host app (for example an
# API-only Rails app) having loaded these frameworks already.
require "rails"
require "pay"
require "active_support"
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
