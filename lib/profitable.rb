# frozen_string_literal: true

require_relative "profitable/version"
require_relative "profitable/error"
require_relative "profitable/mrr_calculator"
require_relative "profitable/numeric_result"
require "pay"
require "active_support/core_ext/numeric/conversions"
require "action_view"

module Profitable
  class << self
    def mrr
      NumericResult.new(MrrCalculator.calculate)
    end

    def arr
      NumericResult.new(calculate_arr)
    end

    def churn
      NumericResult.new(calculate_churn)
    end

    def all_time_revenue
      NumericResult.new(calculate_all_time_revenue)
    end

    def estimated_valuation(multiplier = "3x")
      NumericResult.new(calculate_estimated_valuation(multiplier))
    end

    private

    def calculate_all_time_revenue
      Pay::Charge.sum(:amount)
    end

    def calculate_arr
      (mrr.to_f * 12).round
    end

    def calculate_churn
      # Implement churn calculation here
    end

    def calculate_estimated_valuation(multiplier = "3x")
      multiplier = multiplier.to_s.gsub('x', '').to_f
      (calculate_arr * multiplier).round
    end
  end
end
