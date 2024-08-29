# frozen_string_literal: true

require_relative "profitable/version"
require "pay"
require "active_support/core_ext/numeric/conversions"
require "action_view"

module Profitable
  class Error < StandardError; end

  class << self
    def mrr
      NumericResult.new(calculate_mrr)
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

    def calculate_mrr
      # Implement MRR calculation here
    end

    def calculate_arr
      # Implement ARR calculation here
    end

    def calculate_churn
      # Implement churn calculation here
    end

    def calculate_estimated_valuation(multiplier = "3x")
      multiplier = multiplier.to_s.gsub('x', '').to_f
      calculate_arr * multiplier
    end
  end

  class NumericResult < SimpleDelegator
    include ActionView::Helpers::NumberHelper

    def to_readable(precision = 2)
      "$#{price_in_cents_to_string(self, precision)}"
    end

    private

    def price_in_cents_to_string(price, precision = 2)
      number_with_delimiter(
        number_with_precision(
          (price.to_f / 100), precision: precision
        )
      ).to_s.sub(/\.?0+$/, '')
    end
  end
end
