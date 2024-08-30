require_relative 'processors/base'
require_relative 'processors/stripe_processor'
require_relative 'processors/braintree_processor'
require_relative 'processors/paddle_billing_processor'
require_relative 'processors/paddle_classic_processor'

module Profitable
  class MrrCalculator
    def self.calculate
      subscriptions = Pay::Subscription
        .active
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)

      subscriptions.sum do |subscription|
        process_subscription(subscription)
      end
    rescue => e
      Rails.logger.error("Error calculating total MRR: #{e.message}")
      raise Profitable::Error, "Failed to calculate MRR: #{e.message}"
    end

    def self.process_subscription(subscription)
      return 0 if subscription.nil? || subscription.data.nil?

      processor_class = processor_for(subscription.customer_processor)
      processor_class.new(subscription).calculate_mrr
    rescue => e
      Rails.logger.error("Error calculating MRR for subscription #{subscription.id}: #{e.message}")
      0
    end

    def self.processor_for(processor_name)
      case processor_name
      when 'stripe'
        Processors::StripeProcessor
      when 'braintree'
        Processors::BraintreeProcessor
      when 'paddle_billing'
        Processors::PaddleBillingProcessor
      when 'paddle_classic'
        Processors::PaddleClassicProcessor
      else
        Rails.logger.warn("Unknown processor: #{processor_name}")
        Processors::Base
      end
    end
  end
end
