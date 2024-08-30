module Profitable
  module Processors
    class BraintreeProcessor < Base
      def calculate_mrr
        amount = subscription.data['price']
        quantity = subscription.quantity || 1
        interval = subscription.data['billing_period_unit']
        interval_count = subscription.data['billing_period_frequency'] || 1

        normalize_to_monthly(amount * quantity, interval, interval_count)
      end
    end
  end
end
