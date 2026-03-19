module Profitable
  module Processors
    class PaddleClassicProcessor < Base
      def calculate_mrr
        data = subscription_data
        return 0 if data.nil?

        amount = data['recurring_price']
        return 0 if amount.nil?

        quantity = subscription.quantity || 1
        interval = data['recurring_interval']
        interval_count = 1 # Paddle Classic doesn't have interval_count

        normalize_to_monthly(amount.to_f * quantity, interval, interval_count)
      end
    end
  end
end
