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
      subscriptions = Pay::Subscription
        .active
        .includes(:customer) # Eager load customers
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)

      subscriptions.sum do |subscription|
        begin
          subscription_mrr(subscription)
        rescue => e
          Rails.logger.error("Error calculating MRR for subscription #{subscription.id}: #{e.message}")
          0 # Skip this subscription in case of error
        end
      end
    rescue => e
      Rails.logger.error("Error calculating total MRR: #{e.message}")
      raise Profitable::Error, "Failed to calculate MRR: #{e.message}"
    end

    def subscription_mrr(subscription)
      return 0 if subscription.nil? || subscription.data.nil?

      case subscription.customer_processor
      when 'stripe', 'braintree', 'paddle_billing'
        stripe_braintree_paddle_billing_mrr(subscription)
      when 'paddle_classic'
        paddle_classic_mrr(subscription)
      else
        Rails.logger.warn("Unknown processor for subscription #{subscription.id}: #{subscription.customer_processor}")
        0
      end
    end

    def stripe_braintree_paddle_billing_mrr(subscription)
      subscription_items = subscription.data['subscription_items']
      return 0 if subscription_items.nil? || subscription_items.empty?

      price_data = subscription_items[0]['price']
      return 0 if price_data.nil?

      amount = price_data['unit_amount']
      quantity = subscription.quantity || 1
      interval = price_data.dig('recurring', 'interval')
      interval_count = price_data.dig('recurring', 'interval_count') || 1

      normalize_to_monthly(amount * quantity, interval, interval_count)
    end

    def paddle_classic_mrr(subscription)
      amount = subscription.data['recurring_price']
      quantity = subscription.quantity || 1
      interval = subscription.data['recurring_interval']
      interval_count = 1 # Paddle Classic doesn't have interval_count

      normalize_to_monthly(amount * quantity, interval, interval_count)
    end

    def normalize_to_monthly(amount, interval, interval_count)
      return 0 if amount.nil? || interval.nil? || interval_count.nil?

      case interval.to_s.downcase
      when 'day'
        amount * 30.0 / interval_count
      when 'week'
        amount * 4.0 / interval_count
      when 'month'
        amount / interval_count
      when 'year'
        amount / (12.0 * interval_count)
      else
        Rails.logger.warn("Unknown interval for MRR calculation: #{interval}")
        0
      end
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
