require_relative 'processors/base'
require_relative 'processors/stripe_processor'
require_relative 'processors/braintree_processor'
require_relative 'processors/paddle_billing_processor'
require_relative 'processors/paddle_classic_processor'

module Profitable
  class MrrCalculator
    # Current MRR is just the historical MRR snapshot taken right now.
    # The billable-subscription query lives in Profitable's metrics module so
    # current MRR, MRR-at-date, and growth rates can never drift apart.
    def self.calculate
      Profitable.mrr_at(Time.current).to_i
    rescue Profitable::Error
      raise
    rescue => e
      Rails.logger.error("Error calculating total MRR: #{e.message}")
      raise Profitable::Error, "Failed to calculate MRR: #{e.message}"
    end

    def self.process_subscription(subscription)
      return 0 if subscription.nil?
      return 0 if subscription_data(subscription).nil?

      # Get processor from virtual attribute (set by .select() in queries) or from customer association
      processor_name = subscription.try(:customer_processor) || subscription.customer&.processor

      processor_class = processor_for(processor_name)
      mrr = processor_class.new(subscription).calculate_mrr

      # Ensure MRR is a non-negative number
      mrr.is_a?(Numeric) ? [mrr, 0].max : 0
    rescue => e
      Rails.logger.error("Error calculating MRR for subscription #{subscription.id}: #{e.message}")
      0
    end

    def self.subscription_data(subscription)
      Processors::Base.subscription_data(subscription)
    end

    def self.processor_for(processor_name)
      # MRR parsing needs the processor's price payload stored locally, which Pay
      # only does for Stripe (in `object` on Pay v10+, `data` before that).
      # The remaining adapters only apply when that payload has been backfilled by
      # the application; otherwise unknown or payload-less subscriptions safely
      # contribute zero instead of guessing.
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
