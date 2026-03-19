require_relative 'processors/base'
require_relative 'processors/stripe_processor'
require_relative 'processors/braintree_processor'
require_relative 'processors/paddle_billing_processor'
require_relative 'processors/paddle_classic_processor'

module Profitable
  class MrrCalculator
    def self.calculate
      total_mrr = 0

      # Do not use Pay::Subscription.active here.
      # Pay's active scope is designed for entitlement/access checks and can include
      # free-trial access. MRR needs subscriptions that are billable right now.
      subscriptions = Pay::Subscription
        .where.not(status: Profitable::NEVER_BILLABLE_SUBSCRIPTION_STATUSES)
        .where(
          "(pay_subscriptions.status NOT IN (?) OR (pay_subscriptions.trial_ends_at IS NOT NULL AND pay_subscriptions.trial_ends_at <= ?))",
          Profitable::TRIAL_SUBSCRIPTION_STATUSES,
          Time.current
        )
        .where(
          "(pay_subscriptions.status NOT IN (?) OR pay_subscriptions.ends_at IS NOT NULL)",
          Profitable::CHURNED_STATUSES
        )
        .where(
          "(pay_subscriptions.status != ? OR pay_subscriptions.pause_starts_at IS NOT NULL)",
          'paused'
        )
        .where('COALESCE(pay_subscriptions.trial_ends_at, pay_subscriptions.created_at) <= ?', Time.current)
        .where('pay_subscriptions.pause_starts_at IS NULL OR pay_subscriptions.pause_starts_at > ?', Time.current)
        .where('pay_subscriptions.ends_at IS NULL OR pay_subscriptions.ends_at > ?', Time.current)
        .includes(:customer)
        .select('pay_subscriptions.*, pay_customers.processor as customer_processor')
        .joins(:customer)

      subscriptions.find_each do |subscription|
        mrr = process_subscription(subscription)
        total_mrr += mrr if mrr.is_a?(Numeric) && mrr > 0
      end

      total_mrr
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

    # Pay gem v10+ stores Stripe objects in the `object` column,
    # while older versions used `data`. This method provides backwards compatibility.
    def self.subscription_data(subscription)
      subscription.try(:object) || subscription.try(:data)
    end

    def self.processor_for(processor_name)
      # MRR parsing is only implemented for processors with explicit adapters below.
      # Unknown processors safely fall back to Base and contribute zero until supported.
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
