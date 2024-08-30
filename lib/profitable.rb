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
    DEFAULT_PERIOD = 30.days

    def mrr
      NumericResult.new(MrrCalculator.calculate)
    end

    def arr
      NumericResult.new(calculate_arr)
    end

    def churn(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churn(in_the_last), :percentage)
    end

    def all_time_revenue
      NumericResult.new(calculate_all_time_revenue)
    end

    def estimated_valuation(multiplier = "3x")
      NumericResult.new(calculate_estimated_valuation(multiplier))
    end

    def total_customers
      NumericResult.new(Pay::Customer.count, :integer)
    end

    def total_subscribers
      NumericResult.new(Pay::Subscription.active.distinct.count('customer_id'), :integer)
    end

    def new_customers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(Pay::Customer.where(created_at: in_the_last.ago..Time.current).count, :integer)
    end

    def churned_customers(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churned_customers(in_the_last), :integer)
    end

    def new_mrr(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_new_mrr(in_the_last))
    end

    def churned_mrr(in_the_last: DEFAULT_PERIOD)
      NumericResult.new(calculate_churned_mrr(in_the_last))
    end

    private

    def calculate_all_time_revenue
      Pay::Charge.sum(:amount)
    end

    def calculate_arr
      (mrr.to_f * 12).round
    end

    def calculate_estimated_valuation(multiplier = "3x")
      multiplier = multiplier.to_s.gsub('x', '').to_f
      (calculate_arr * multiplier).round
    end

    def calculate_churn(period)
      start_date = period.ago
      total_subscribers_start = Pay::Subscription.active.where('created_at < ?', start_date).distinct.count('customer_id')
      churned = calculate_churned_customers(period)
      return 0 if total_subscribers_start == 0
      (churned.to_f / total_subscribers_start * 100).round(2)
    end

    def churned_subscriptions(period = DEFAULT_PERIOD)
      Pay::Subscription
        .where(status: ['canceled', 'ended'])
        .where(ends_at: period.ago..Time.current)
    end

    def calculate_churned_customers(period)
      churned_subscriptions(period).distinct.count('customer_id')
    end

    def calculate_churned_mrr(period)
      churned_subscriptions(period).sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

    def calculate_new_mrr(period)
      new_subscriptions = Pay::Subscription
        .where(created_at: period.ago..Time.current)
        .active
        .where.not(status: ['trialing', 'paused'])
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)

      new_subscriptions.sum do |subscription|
        MrrCalculator.process_subscription(subscription)
      end
    end

  end
end
