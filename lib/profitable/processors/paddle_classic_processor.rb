module Profitable
  module Processors
    class PaddleClassicProcessor < Base
      def calculate_mrr
        amount = subscription.data['recurring_price']
        quantity = subscription.quantity || 1
        interval = subscription.data['recurring_interval']
        interval_count = 1 # Paddle Classic doesn't have interval_count

        normalize_to_monthly(amount * quantity, interval, interval_count)
      end
    end
  end
end
