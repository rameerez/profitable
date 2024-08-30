module Profitable
  module Processors
    class PaddleBillingProcessor < Base
      def calculate_mrr
        price_data = subscription.data['items']&.first&.dig('price')
        return 0 if price_data.nil?

        amount = price_data['unit_price']['amount']
        quantity = subscription.quantity || 1
        interval = price_data['billing_cycle']['interval']
        interval_count = price_data['billing_cycle']['frequency']

        normalize_to_monthly(amount * quantity, interval, interval_count)
      end
    end
  end
end
