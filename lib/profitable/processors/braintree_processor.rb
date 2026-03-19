module Profitable
  module Processors
    class BraintreeProcessor < Base
      def calculate_mrr
        data = subscription_data
        return 0 if data.nil?

        amount = data['price']
        return 0 if amount.nil?

        quantity = subscription.quantity || 1
        interval = data['billing_period_unit']
        interval_count = data['billing_period_frequency'] || 1

        normalize_to_monthly(amount.to_f * quantity, interval, interval_count)
      end
    end
  end
end
