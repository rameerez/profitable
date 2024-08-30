module Profitable
  module Processors
    class StripeProcessor < Base
      def calculate_mrr
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
    end
  end
end
