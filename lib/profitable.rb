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
      end_date = Date.today
      start_date = end_date - 30.days

      total_subscribers_start = Pay::Subscription
        .where('created_at < ?', start_date)
        .where.not(status: nil)
        .distinct.count('customer_id')

      churned_subscribers = Pay::Subscription
        .where(status: ['canceled', 'ended'])
        .where(ends_at: start_date..end_date)
        .distinct.count('customer_id')

      return 0 if total_subscribers_start == 0
      ((churned_subscribers.to_f / total_subscribers_start) * 100).round(2)
    end

    def calculate_estimated_valuation(multiplier = "3x")
      multiplier = multiplier.to_s.gsub('x', '').to_f
      (calculate_arr * multiplier).round
    end
  end
end
